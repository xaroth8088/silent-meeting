import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum LauncherSmoke {
    static func check(frame: CVPixelBuffer, soundtracks: URL) throws {
        var description: CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCVPixelFormatType_32BGRA, width: 1920, height: 1080,
            extensions: nil, formatDescriptionOut: &description
        ) == noErr)
        let output = OBSFrames(format: description!)!.sample(from: frame, at: CameraFormat.hostTime)!
        precondition(CVPixelBufferGetWidth(output.imageBuffer!) == 1920)
        precondition(CVPixelBufferGetHeight(output.imageBuffer!) == 1080)
        precondition(CVPixelBufferGetPixelFormatType(output.imageBuffer!) == kCVPixelFormatType_32BGRA)

        try checkSoundtrack(soundtracks)
        if !BlackHolePiano.deviceAvailable {
            do {
                try BlackHolePiano().start(soundtracks: soundtracks)
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
        print("Launcher OBS frame format, sentiment cues, BlackHole stereo crossfade and missing-device guard, and checksum validation passed.")
    }

    private static func checkSoundtrack(_ directory: URL) throws {
        precondition(SoundtrackMood(score: 0.8) == .upbeat && SoundtrackMood(score: -0.9) == .somber)
        precondition(SoundtrackMood(score: 0.79) == .neutral && SoundtrackMood(score: -0.8) == .neutral)
        precondition(SoundtrackMood(score: .nan) == nil)

        let score = SoundtrackSentiment()
        let cue = DialogueCards.prepare("[inhales] That's amazing news!", sentiment: score)!
        precondition(cue.text == "That's amazing news!")
        let deadline = DispatchTime.now() + .seconds(2)
        while cue.cue?.mood.withLock({ $0 }) == nil && DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        precondition(cue.cue?.mood.withLock({ $0 }) == .upbeat)

        let pending = SoundtrackCue()
        var cards = DialogueCards()
        cards.enqueue(.init(text: String(repeating: "word ", count: 40), cue: pending))
        let time = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        precondition(cards.page(at: time)?.cue === pending && pending.mood.withLock({ $0 }) == nil)
        precondition(cards.page(at: time + .seconds(8))?.cue === pending)

        let frames = 1_024
        let count = 6 * frames
        var stereo = [Float](repeating: 0, count: frames * 2)
        var mix = try PianoMix(soundtracks: directory)
        var previous = SoundtrackMood.neutral
        var previousPosition = 0
        for mood in [SoundtrackMood.upbeat, .somber, .neutral] {
            let incoming = try prefix(mood, frames: count, directory: directory)
            let outgoing = try prefix(previous, frames: previousPosition + count, directory: directory)
            for offset in stride(from: 0, to: count, by: frames) {
                stereo.withUnsafeMutableBufferPointer {
                    mix.write(into: $0.baseAddress!, frames: frames, mood: mood)
                }
                for index in 0..<frames {
                    let position = offset + index
                    let alpha = min(1, Float(position + 1) / Float(PianoMix.fadeFrames))
                    let expected = outgoing[previousPosition + position] * (1 - alpha) + incoming[position] * alpha
                    precondition(abs(stereo[index * 2] - expected) < 0.00001)
                    precondition(stereo[index * 2] == stereo[index * 2 + 1])
                }
            }
            previous = mood
            previousPosition = count
        }
    }

    private static func prefix(_ mood: SoundtrackMood, frames: Int, directory: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: directory.appendingPathComponent(mood.rawValue + ".mp3"),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
        try file.read(into: buffer)
        precondition(buffer.frameLength == frames)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: frames))
    }
}
