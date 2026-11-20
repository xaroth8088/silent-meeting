import AppKit
import Combine
@preconcurrency import AVFoundation
import SwiftUI
import SystemExtensions

@main
struct SilentMeetingApp: App {
    @StateObject private var studio = Studio()

    var body: some Scene {
        WindowGroup("Silent Meeting") {
            StudioView(studio: studio)
                .frame(minWidth: 620, minHeight: 525)
                .padding(24)
        }
        .defaultSize(width: 700, height: 600)
        .windowResizability(.contentMinSize)
    }
}

struct StudioView: View {
    @ObservedObject var studio: Studio
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Silent Meeting").font(.system(.largeTitle, design: .serif).bold())
                Spacer()
                Label(studio.sending ? "Camera live" : "Camera idle",
                      systemImage: studio.sending ? "video.fill" : "video.slash")
                    .foregroundStyle(studio.sending ? Color.green : Color.secondary)
            }
            ZStack {
                Rectangle().fill(Color(white: 0.045))
                if let preview = studio.preview {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit()
                        .accessibilityLabel("Processed camera preview")
                } else {
                    Text("Camera preview").foregroundStyle(.white.opacity(0.65))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 20) {
                Picker("Camera", selection: $studio.cameraID) {
                    ForEach(studio.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                Picker("Microphone", selection: $studio.microphoneID) {
                    ForEach(studio.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
            }
            .disabled(studio.running || studio.busy)

            HStack(spacing: 12) {
                if !studio.cameraEnabled {
                    Button("Enable Virtual Camera") { studio.enableCamera() }
                        .disabled(studio.installing || studio.busy)
                }
                Button(studio.running ? "Stop" : "Start") { studio.running ? studio.stop() : studio.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(studio.busy || (!studio.running &&
                        (!studio.cameraEnabled || studio.cameraID.isEmpty || studio.microphoneID.isEmpty)))
                Spacer()
                Label(studio.microphoneInstalled ? "Piano microphone ready" : "Piano microphone unavailable",
                      systemImage: studio.microphoneInstalled ? "music.note" : "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if let message = studio.message {
                Text(message).font(.callout)
            } else {
                Text("In your meeting app, choose Silent Meeting Camera and Silent Meeting Piano.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { studio.refreshDevices() }
        .onReceive(timer) { _ in studio.refreshDevices() }
    }
}

final class Studio: NSObject, ObservableObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    @Published var cameraID = ""
    @Published var microphoneID = ""
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var microphones: [AVCaptureDevice] = []
    @Published private(set) var cameraEnabled = false
    @Published private(set) var microphoneInstalled = false
    @Published private(set) var running = false
    @Published private(set) var busy = false
    @Published private(set) var installing = false
    @Published private(set) var sending = false
    @Published private(set) var preview: CGImage?
    @Published private(set) var message: String?

    private let captureQueue = DispatchQueue(label: "Silent Meeting capture configuration", qos: .userInitiated)
    private var pipeline: CapturePipeline?
    private var sessionID: UUID?

    func refreshDevices() {
        let video = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                     mediaType: .video, position: .unspecified).devices
        let audio = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone],
                                                     mediaType: .audio, position: .unspecified).devices
        cameraEnabled = video.contains(where: isVirtualCamera)
        microphoneInstalled = audio.contains(where: isVirtualMicrophone)
        cameras = video.filter { !isVirtualCamera($0) }
        microphones = audio.filter { !isVirtualMicrophone($0) }
        if !running && !busy {
            if !cameras.contains(where: { $0.uniqueID == cameraID }) {
                cameraID = cameras.first?.uniqueID ?? ""
            }
            if !microphones.contains(where: { $0.uniqueID == microphoneID }) {
                microphoneID = microphones.first?.uniqueID ?? ""
            }
        }
    }

    private func isVirtualCamera(_ device: AVCaptureDevice) -> Bool {
        device.uniqueID.caseInsensitiveCompare(CameraFormat.deviceID.uuidString) == .orderedSame ||
            device.localizedName == CameraFormat.name
    }

    private func isVirtualMicrophone(_ device: AVCaptureDevice) -> Bool {
        device.uniqueID == "io.github.xaroth8088.silent-meeting.piano-input" ||
            device.localizedName == "Silent Meeting Piano"
    }

    func enableCamera() {
        guard Bundle.main.object(forInfoDictionaryKey: "SilentMeetingSigned") as? Bool == true,
              let id = Bundle.main.object(forInfoDictionaryKey: "SilentMeetingCameraExtension") as? String else {
            message = "This development build needs Apple signing before macOS can enable its virtual camera."
            return
        }
        message = "Approve the Silent Meeting camera extension in System Settings if prompted."
        installing = true
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: id, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        message = "Allow the camera extension in System Settings under Login Items & Extensions."
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        installing = false
        message = result == .willCompleteAfterReboot ? "Restart your Mac to enable the camera." : nil
        refreshDevices()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        installing = false
        message = error.localizedDescription
        refreshDevices()
    }

    func start() {
        guard let camera = cameras.first(where: { $0.uniqueID == cameraID }),
              let microphone = microphones.first(where: { $0.uniqueID == microphoneID }) else { return }
        busy = true
        message = nil
        Task { @MainActor [self] in
            let videoAllowed = await AVCaptureDevice.requestAccess(for: .video)
            let audioAllowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard videoAllowed && audioAllowed else {
                busy = false
                message = "Allow Silent Meeting to use your camera and microphone in System Settings → Privacy & Security."
                return
            }
            let id = UUID()
            sessionID = id
            let capture = CapturePipeline { [weak self] thumbnail, connected in
                DispatchQueue.main.async {
                    guard let self, self.sessionID == id else { return }
                    self.preview = thumbnail
                    self.sending = connected
                }
            }
            pipeline = capture
            captureQueue.async {
                let outcome = Result { try capture.start(camera: camera, microphone: microphone) }
                DispatchQueue.main.async {
                    self.busy = false
                    switch outcome {
                    case .success:
                        self.running = true
                    case .failure(let error):
                        self.pipeline = nil
                        self.sessionID = nil
                        self.message = error.localizedDescription
                    }
                }
            }
        }
    }

    func stop() {
        guard let pipeline else { return }
        sessionID = nil
        busy = true
        captureQueue.async {
            pipeline.stop()
            DispatchQueue.main.async {
                self.pipeline = nil
                self.running = false
                self.sending = false
                self.preview = nil
                self.busy = false
            }
        }
    }
}
