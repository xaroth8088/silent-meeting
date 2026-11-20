import CoreMediaIO
import Foundation

final class CameraSink {
    private var connection: (device: CMIOObjectID, stream: CMIOStreamID, queue: CMSimpleQueue)?
    private var retryAfter = DispatchTime(uptimeNanoseconds: 0)
    private var fullSince: DispatchTime?

    private func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func objectIDs(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
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

    private func isSilentMeeting(_ device: CMIOObjectID) -> Bool {
        var property = address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout.size(ofValue: value))
        guard CMIOObjectGetPropertyData(device, &property, 0, nil, size, &used, &value) == noErr,
              let uid = value?.takeRetainedValue() as String? else { return false }
        return uid.caseInsensitiveCompare(CameraFormat.deviceID.uuidString) == .orderedSame
    }

    private func isSink(_ stream: CMIOStreamID) -> Bool {
        var property = address(CMIOObjectPropertySelector(kCMIOStreamPropertyDirection))
        var direction: UInt32 = 1
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout.size(ofValue: direction))
        return CMIOObjectGetPropertyData(stream, &property, 0, nil, size, &used, &direction) == noErr && direction == 0
    }

    private func connect() {
        guard let device = objectIDs(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            .first(where: isSilentMeeting),
              let stream = objectIDs(device, CMIOObjectPropertySelector(kCMIODevicePropertyStreams)).first(where: isSink)
        else { return }
        var borrowed: Unmanaged<CMSimpleQueue>?
        guard CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &borrowed) == noErr,
              let bufferQueue = borrowed?.takeRetainedValue(),
              CMIODeviceStartStream(device, stream) == noErr else { return }
        connection = (device, stream, bufferQueue)
    }

    // All calls come from the camera sample queue.
    func send(_ sample: CMSampleBuffer) -> Bool {
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
        fullSince = nil
        retryAfter = DispatchTime(uptimeNanoseconds: 0)
    }
}
