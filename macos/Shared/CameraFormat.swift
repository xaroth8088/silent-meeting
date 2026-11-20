import CoreMedia
import CoreVideo
import Foundation

enum CameraFormat {
    static let name = "Silent Meeting Camera"
    static let deviceID = UUID(uuidString: "912B0AF7-D598-4967-BDDD-69BB3D3BA719")!
    static let sourceID = UUID(uuidString: "118E4DC8-DEFB-4BE4-8D50-F5455981CE55")!
    static let sinkID = UUID(uuidString: "22E54F8A-67FF-4278-9A90-83B0B573D6AB")!
    static let width = 1280
    static let height = 720
    static let framesPerSecond: Int32 = 30
    static let duration = CMTime(value: 1, timescale: framesPerSecond)

    static let description: CMVideoFormatDescription = {
        var format: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width), height: Int32(height), extensions: nil, formatDescriptionOut: &format
        )
        precondition(status == noErr)
        return format!
    }()

    static func makePool() -> CVPixelBufferPool {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pool: CVPixelBufferPool?
        precondition(CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess)
        return pool!
    }

    static func allocate(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey as String: 12]
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits as CFDictionary, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }

    static var hostTime: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    static func sample(from buffer: CVPixelBuffer, at time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: description,
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        return status == noErr ? sample : nil
    }
}
