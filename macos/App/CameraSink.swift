import CoreMediaIO
import CoreImage
import Foundation

final class CameraSink {
    enum Target {
        case silentMeeting, obs

        var uid: String {
            switch self {
            case .silentMeeting: return CameraFormat.deviceID.uuidString
            case .obs: return "7626645E-4425-469E-9D8B-97E0FA59AC75"
            }
        }
    }

    private let target: Target
    private var connection: (device: CMIOObjectID, stream: CMIOStreamID, queue: CMSimpleQueue)?
    private var obsFrames: OBSFrames?
    private var retryAfter = DispatchTime(uptimeNanoseconds: 0)
    private var fullSince: DispatchTime?

    init(target: Target = .silentMeeting) { self.target = target }

    static func available(_ target: Target) -> Bool {
        endpoint(target) != nil
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func objectIDs(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
        var property = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        var used: UInt32 = 0
        guard objects.withUnsafeMutableBytes({
            CMIOObjectGetPropertyData(object, &property, 0, nil, size, &used, $0.baseAddress!)
        }) == noErr else { return [] }
        return Array(objects.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride))
    }

    private static func matches(_ device: CMIOObjectID, target: Target) -> Bool {
        var property = address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout.size(ofValue: value))
        guard CMIOObjectGetPropertyData(device, &property, 0, nil, size, &used, &value) == noErr,
              let uid = value?.takeRetainedValue() as String? else { return false }
        return uid.caseInsensitiveCompare(target.uid) == .orderedSame
    }

    private static func isSink(_ stream: CMIOStreamID) -> Bool {
        var property = address(CMIOObjectPropertySelector(kCMIOStreamPropertyDirection))
        var direction: UInt32 = 1
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout.size(ofValue: direction))
        return CMIOObjectGetPropertyData(stream, &property, 0, nil, size, &used, &direction) == noErr && direction == 0
    }

    private static func endpoint(_ target: Target) -> (CMIOObjectID, CMIOStreamID)? {
        guard let device = objectIDs(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            .first(where: { matches($0, target: target) }),
              let stream = objectIDs(device, CMIOObjectPropertySelector(kCMIODevicePropertyStreams)).first(where: isSink)
        else { return nil }
        return (device, stream)
    }

    private func connect() {
        guard let (device, stream) = Self.endpoint(target) else { return }
        if target == .obs {
            var property = Self.address(CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescription))
            var value: Unmanaged<CMFormatDescription>?
            var used: UInt32 = 0
            let bytes = UInt32(MemoryLayout.size(ofValue: value))
            guard CMIOObjectGetPropertyData(stream, &property, 0, nil, bytes, &used, &value) == noErr,
                  let format = value?.takeRetainedValue(), let frames = OBSFrames(format: format)
            else { return }
            obsFrames = frames
        }
        var borrowed: Unmanaged<CMSimpleQueue>?
        guard CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &borrowed) == noErr,
              let bufferQueue = borrowed?.takeRetainedValue(),
              CMIODeviceStartStream(device, stream) == noErr else { return }
        connection = (device, stream, bufferQueue)
    }

    // All calls come from the camera sample queue.
    func send(_ frame: CVPixelBuffer) -> Bool {
        let now = DispatchTime.now()
        if connection == nil, now >= retryAfter {
            retryAfter = now + .seconds(1)
            connect()
        }
        guard let connection else { return false }
        if CMSimpleQueueGetCount(connection.queue) >= min(2, CMSimpleQueueGetCapacity(connection.queue)) {
            if let fullSince, now >= fullSince + .seconds(1) {
                stop()
                retryAfter = now + .seconds(1)
                return false
            }
            if fullSince == nil { fullSince = now }
            return true
        }
        fullSince = nil
        let time = CameraFormat.hostTime
        let sample = obsFrames?.sample(from: frame, at: time) ??
            (target == .silentMeeting ? CameraFormat.sample(from: frame, at: time) : nil)
        guard let sample else { return false }
        let retained = Unmanaged.passRetained(sample)
        guard CMSimpleQueueEnqueue(connection.queue, element: retained.toOpaque()) == noErr else {
            retained.release()
            return false
        }
        return true
    }

    func stop() {
        if let connection {
            CMIODeviceStopStream(connection.device, connection.stream)
            // CMIO consumes the retain for delivered buffers. This queue owns the leftovers.
            while let pointer = CMSimpleQueueDequeue(connection.queue) {
                Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
            }
            self.connection = nil
        }
        obsFrames = nil
        fullSince = nil
        retryAfter = DispatchTime(uptimeNanoseconds: 0)
    }
}

// OBS advertises a fixed BGRA size for its CMIO stream even when the physical camera is smaller.
final class OBSFrames {
    private let canvas: CGRect
    private let description: CMVideoFormatDescription
    private let pool: CVPixelBufferPool?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorspace = CGColorSpaceCreateDeviceRGB()

    init?(format: CMFormatDescription) {
        guard CMFormatDescriptionGetMediaType(format) == kCMMediaType_Video,
              CMFormatDescriptionGetMediaSubType(format) == kCVPixelFormatType_32BGRA else { return nil }
        let width = Int(format.dimensions.width)
        let height = Int(format.dimensions.height)
        guard width > 0, height > 0, width <= 4096, height <= 2160 else { return nil }
        canvas = CGRect(x: 0, y: 0, width: width, height: height)
        if width == CameraFormat.width && height == CameraFormat.height {
            description = CameraFormat.description
            pool = nil
        } else {
            var description: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCVPixelFormatType_32BGRA,
                                                  width: Int32(width), height: Int32(height), extensions: nil,
                                                  formatDescriptionOut: &description) == noErr,
                  let description else { return nil }
            self.description = description
            pool = CameraFormat.makePool(width: width, height: height)
        }
    }

    func sample(from source: CVPixelBuffer, at time: CMTime) -> CMSampleBuffer? {
        guard let pool else { return CameraFormat.sample(from: source, at: time) }
        guard let output = CameraFormat.allocate(from: pool) else { return nil }
        let image = CIImage(cvPixelBuffer: source)
        let scale = min(canvas.width / image.extent.width, canvas.height / image.extent.height)
        let center = CGAffineTransform(translationX: (canvas.width - image.extent.width * scale) / 2,
                                       y: (canvas.height - image.extent.height * scale) / 2)
        let background = CIImage(color: .black).cropped(to: canvas)
        let fitted = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(center))
            .composited(over: background)
        context.render(fitted, to: output, bounds: canvas, colorSpace: colorspace)
        return CameraFormat.sample(from: output, at: time, format: description)
    }
}
