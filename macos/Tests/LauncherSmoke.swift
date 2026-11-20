import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum LauncherSmoke {
    static func check(frame: CVPixelBuffer, soundtrack: URL) throws {
        var description: CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCVPixelFormatType_32BGRA, width: 1920, height: 1080,
            extensions: nil, formatDescriptionOut: &description
        ) == noErr)
        let output = OBSFrames(format: description!)!.sample(from: frame, at: CameraFormat.hostTime)!
        precondition(CVPixelBufferGetWidth(output.imageBuffer!) == 1920)
        precondition(CVPixelBufferGetHeight(output.imageBuffer!) == 1080)
        precondition(CVPixelBufferGetPixelFormatType(output.imageBuffer!) == kCVPixelFormatType_32BGRA)

        let track = try AVAudioFile(forReading: soundtrack, commonFormat: .pcmFormatFloat32, interleaved: false)
        precondition(track.processingFormat.channelCount == 1 && track.length > 48_000)
        let mono: [Float] = [0.125, -0.25, 0.375]
        var position = 1
        var stereo = [Float](repeating: 0, count: 8)
        mono.withUnsafeBufferPointer { source in
            stereo.withUnsafeMutableBufferPointer { destination in
                BlackHolePiano.copyLoop(samples: source.baseAddress!, count: source.count,
                                        position: &position, into: destination.baseAddress!, frames: 4)
            }
        }
        precondition(stereo == [-0.25, -0.25, 0.375, 0.375, 0.125, 0.125, -0.25, -0.25] && position == 2)
        if !BlackHolePiano.deviceAvailable {
            do {
                try BlackHolePiano().start(track: soundtrack)
                preconditionFailure("The piano destination must not fall back to the system output.")
            } catch {
                precondition(error.localizedDescription.contains("BlackHole 2ch"))
            }
        }

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("silent-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: fixture) }
        try Data("abc".utf8).write(to: fixture)
        let download = LauncherSetup.Download(
            url: fixture,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        let valid = try download.verified(fixture)
        let bad = try LauncherSetup.blackHole.verified(fixture)
        precondition(valid && !bad)
        print("Launcher OBS frame format, BlackHole stereo loop and missing-device guard, and checksum validation passed.")
    }
}
