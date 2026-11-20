import CoreMediaIO
import CoreAudio
import CoreVideo
import Foundation
import Security
import os

final class Stream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    let direction: CMIOExtensionStream.Direction
    weak var camera: Camera?

    init(camera: Camera, direction: CMIOExtensionStream.Direction) {
        self.camera = camera
        self.direction = direction
        super.init()
        let source = direction == .source
        stream = CMIOExtensionStream(
            localizedName: source ? "Video" : "Silent Meeting App Feed",
            streamID: source ? CameraFormat.sourceID : CameraFormat.sinkID,
            direction: direction, clockType: .hostTime, source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] {
        [CMIOExtensionStreamFormat(formatDescription: CameraFormat.description,
                                   maxFrameDuration: CameraFormat.duration, minFrameDuration: CameraFormat.duration,
                                   validFrameDurations: nil)]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        var properties: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink {
            properties.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup])
        }
        return properties
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { result.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { result.frameDuration = CameraFormat.duration }
        if properties.contains(.streamSinkBufferQueueSize) { result.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { result.sinkBuffersRequiredForStartup = 1 }
        return result
    }

    func setStreamProperties(_ properties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        direction == .source || camera?.authorizeProducer(client) == true
    }

    func startStream() throws {
        camera?.start(direction)
    }

    func stopStream() throws {
        camera?.stop(direction)
    }
}

final class Camera: NSObject, CMIOExtensionDeviceSource {
    private let queue = DispatchQueue(label: "Silent Meeting Camera delivery", qos: .userInteractive)
    private var consumers = 0
    private var producer: CMIOExtensionClient?
    private var producerRunning = false
    private var consuming = false
    private var generation = 0
    private var latest: CVPixelBuffer?
    private var lastArrival = CMTime.invalid
    private var previousStandby = true
    private var timer: DispatchSourceTimer?
    private let producerRequirement: SecRequirement?
    private let log = Logger(subsystem: "io.github.xaroth8088.silent-meeting", category: "camera-extension")
    private let standby: CVPixelBuffer
    private(set) var device: CMIOExtensionDevice!
    private lazy var source = Stream(camera: self, direction: .source)
    private lazy var sink = Stream(camera: self, direction: .sink)

    override init() {
        let team = Bundle.main.object(forInfoDictionaryKey: "SilentMeetingTeam") as? String ?? ""
        let host = Bundle.main.object(forInfoDictionaryKey: "SilentMeetingHost") as? String ?? ""
        var requirement: SecRequirement?
        if !team.isEmpty && !host.isEmpty {
            let expression = "anchor apple generic and identifier \"\(host)\" and certificate leaf[subject.OU] = \"\(team)\""
            SecRequirementCreateWithString(expression as CFString, [], &requirement)
        }
        producerRequirement = requirement
        let pool = CameraFormat.makePool()
        standby = CameraFormat.allocate(from: pool)!
        Intertitle.draw("Open Silent Meeting to start the camera.", into: standby, standby: true)
        super.init()
        device = CMIOExtensionDevice(localizedName: CameraFormat.name, deviceID: CameraFormat.deviceID,
                                     legacyDeviceID: CameraFormat.deviceID.uuidString, source: self)
    }

    func registerStreams() throws {
        try device.addStream(source.stream)
        try device.addStream(sink.stream)
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceModel, .deviceTransportType] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let result = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) { result.model = CameraFormat.name }
        if properties.contains(.deviceTransportType) { result.transportType = Int(kAudioDeviceTransportTypeVirtual) }
        return result
    }

    func setDeviceProperties(_ properties: CMIOExtensionDeviceProperties) throws {}

    func authorizeProducer(_ client: CMIOExtensionClient) -> Bool {
        guard let producerRequirement else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: client.pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, [], producerRequirement) == errSecSuccess else {
            log.error("Rejected an unsigned or unrelated camera producer.")
            return false
        }
        return queue.sync {
            if producerRunning || (producer != nil && producer?.clientID != client.clientID) { return false }
            producer = client
            return true
        }
    }

    func disconnected(_ client: CMIOExtensionClient) {
        queue.async {
            guard self.producer?.clientID == client.clientID else { return }
            self.clearProducer()
            self.updateTimer()
        }
    }

    func start(_ direction: CMIOExtensionStream.Direction) {
        queue.sync {
            if direction == .source { consumers += 1 } else { producerRunning = true }
            updateTimer()
        }
    }

    func stop(_ direction: CMIOExtensionStream.Direction) {
        queue.sync {
            if direction == .source { consumers = max(0, consumers - 1) } else { clearProducer() }
            updateTimer()
        }
    }

    private func clearProducer() {
        producer = nil
        producerRunning = false
        consuming = false
        generation += 1
        latest = nil
        lastArrival = .invalid
    }

    private func updateTimer() {
        if consumers == 0 && !producerRunning {
            timer?.cancel()
            timer = nil
        } else if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / Int(CameraFormat.framesPerSecond)),
                           leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    private func tick() {
        if producerRunning, let producer, !consuming {
            consuming = true
            let generation = generation
            sink.stream.consumeSampleBuffer(from: producer) { [weak self] sample, sequence, _, _, error in
                guard let self else { return }
                self.queue.async {
                    guard self.generation == generation else { return }
                    self.consuming = false
                    guard error == nil, let sample else { return }
                    let timestamp = CameraFormat.hostTime
                    let nanos = UInt64(CMTimeConvertScale(timestamp, timescale: 1_000_000_000, method: .default).value)
                    self.sink.stream.notifyScheduledOutputChanged(
                        CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: nanos)
                    )
                    guard let frame = sample.imageBuffer,
                          CVPixelBufferGetWidth(frame) == CameraFormat.width,
                          CVPixelBufferGetHeight(frame) == CameraFormat.height,
                          CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32BGRA else { return }
                    self.latest = frame
                    self.lastArrival = timestamp
                }
            }
        }
        guard consumers > 0 else { return }
        let now = CameraFormat.hostTime
        let recent = lastArrival.isValid && (now - lastArrival).seconds < 0.75
        let frame = recent ? latest ?? standby : standby
        guard let sample = CameraFormat.sample(from: frame, at: now) else { return }
        let changed = previousStandby != !recent
        previousStandby = !recent
        let nanos = UInt64(CMTimeConvertScale(now, timescale: 1_000_000_000, method: .default).value)
        source.stream.send(sample, discontinuity: changed ? [.sampleDropped] : [], hostTimeInNanoseconds: nanos)
    }
}

final class Provider: NSObject, CMIOExtensionProviderSource {
    private let camera = Camera()
    private(set) var provider: CMIOExtensionProvider!

    override init() {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: nil)
    }

    func registerDevice() throws {
        try camera.registerStreams()
        try provider.addDevice(camera.device)
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let result = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { result.manufacturer = "Silent Meeting" }
        return result
    }

    func setProviderProperties(_ properties: CMIOExtensionProviderProperties) throws {}
    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) { camera.disconnected(client) }
}

do {
    let service = Provider()
    try service.registerDevice()
    CMIOExtensionProvider.startService(provider: service.provider)
    withExtendedLifetime(service) { CFRunLoopRun() }
} catch {
    FileHandle.standardError.write(Data("Silent Meeting camera: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
