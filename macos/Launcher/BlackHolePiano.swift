@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class BlackHolePiano: @unchecked Sendable {
    static let uid = "BlackHole2ch_UID"
    static let deviceName = "BlackHole 2ch"
    private static let framesPerBuffer: UInt32 = 1024
    private static let bytesPerFrame = UInt32(2 * MemoryLayout<Float>.size)

    private var queue: AudioQueueRef?
    private var track: AVAudioPCMBuffer?
    private var position = 0

    private static var deviceID: AudioDeviceID? {
        let uid = Self.uid as CFString
        var reference = Unmanaged.passUnretained(uid)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout.size(ofValue: id))
        let status = withExtendedLifetime(uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout.size(ofValue: reference)), &reference, &size, &id)
        }
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    static var deviceAvailable: Bool {
        guard let id = deviceID else { return false }
        for scope in [kAudioDevicePropertyScopeInput, kAudioDevicePropertyScopeOutput] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &streamSize) == noErr, streamSize > 0
            else { return false }
        }
        return true
    }

    static var systemOutputUsesBlackHole: Bool {
        guard let id = deviceID else { return false }
        return [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice].contains { selector in
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            var output = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout.size(ofValue: output))
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property,
                                             0, nil, &size, &output) == noErr else { return false }
            if output == id { return true }
            property.mSelector = kAudioAggregateDevicePropertyActiveSubDeviceList
            guard AudioObjectHasProperty(output, &property),
                  AudioObjectGetPropertyDataSize(output, &property, 0, nil, &size) == noErr,
                  size >= MemoryLayout<AudioDeviceID>.stride else { return false }
            var members = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.stride)
            let status = members.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(output, &property, 0, nil, &size, $0.baseAddress!)
            }
            return status == noErr && members.contains(id)
        }
    }

    // Called only by the launcher lifecycle queue. There is deliberately no default-device route.
    func start(track url: URL) throws {
        guard Self.deviceAvailable else { throw PianoError.unavailable }
        guard !Self.systemOutputUsesBlackHole else { throw PianoError.systemOutput }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0, file.length <= 12_000_000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw PianoError.soundtrack }
        try file.read(into: buffer)
        guard buffer.frameLength > 0, buffer.floatChannelData != nil else { throw PianoError.soundtrack }

        var format = AudioStreamBasicDescription(
            mSampleRate: file.processingFormat.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: Self.bytesPerFrame,
            mFramesPerPacket: 1, mBytesPerFrame: Self.bytesPerFrame, mChannelsPerFrame: 2,
            mBitsPerChannel: 32, mReserved: 0
        )
        var created: AudioQueueRef?
        let status = AudioQueueNewOutput(&format, { context, queue, output in
            guard let context else { return }
            _ = Unmanaged<BlackHolePiano>.fromOpaque(context).takeUnretainedValue().enqueue(queue, output)
        }, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &created)
        guard status == noErr, let created else { throw PianoError.routing(status) }
        queue = created
        track = buffer
        position = 0

        do {
            let uid = Self.uid as CFString
            var reference = Unmanaged.passUnretained(uid)
            try withExtendedLifetime(uid) {
                try check(AudioQueueSetProperty(created, kAudioQueueProperty_CurrentDevice, &reference,
                                                UInt32(MemoryLayout.size(ofValue: reference))))
            }
            for _ in 0..<3 {
                var output: AudioQueueBufferRef?
                try check(AudioQueueAllocateBuffer(created, Self.framesPerBuffer * Self.bytesPerFrame, &output))
                guard let output else { throw PianoError.soundtrack }
                try check(enqueue(created, output))
            }
            try check(AudioQueueStart(created, nil))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let queue {
            AudioQueueDispose(queue, true)
            self.queue = nil
        }
        track = nil
    }

    deinit { stop() }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw PianoError.routing(status) }
    }

    private func enqueue(_ queue: AudioQueueRef, _ output: AudioQueueBufferRef) -> OSStatus {
        guard let track, let samples = track.floatChannelData?[0] else { return kAudioQueueErr_CannotStart }
        let frames = Int(Self.framesPerBuffer)
        let stereo = output.pointee.mAudioData.assumingMemoryBound(to: Float.self)
        Self.copyLoop(samples: samples, count: Int(track.frameLength), position: &position, into: stereo, frames: frames)
        output.pointee.mAudioDataByteSize = Self.framesPerBuffer * Self.bytesPerFrame
        return AudioQueueEnqueueBuffer(queue, output, 0, nil)
    }

    static func copyLoop(samples: UnsafePointer<Float>, count: Int, position: inout Int,
                         into stereo: UnsafeMutablePointer<Float>, frames: Int) {
        for index in 0..<frames {
            let sample = samples[position]
            stereo[index * 2] = sample
            stereo[index * 2 + 1] = sample
            position += 1
            if position == count { position = 0 }
        }
    }
}

private enum PianoError: LocalizedError {
    case unavailable, systemOutput, soundtrack, routing(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "BlackHole 2ch isn't available. Finish its installation and restart your Mac."
        case .systemOutput: return "Choose speakers or headphones as your Mac's audio output to keep other sounds out of BlackHole."
        case .soundtrack: return "The bundled piano track couldn't be opened."
        case .routing(let code): return "Couldn't send piano to BlackHole 2ch (Core Audio \(code))."
        }
    }
}
