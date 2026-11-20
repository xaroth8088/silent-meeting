import CoreVideo
import Foundation

@main
struct Smoke {
    static func main() throws {
        let model = URL(fileURLWithPath: CommandLine.arguments[1])
        let pcm = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let recognizer = WhisperRecognizer(model: model)!
        let endpointer = VoiceEndpointer()!
        let speech = pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        var segments: [VoiceEndpointer.Chunk] = []
        for offset in stride(from: 0, to: speech.count, by: 483) {
            endpointer.append(Array(speech[offset..<min(offset + 483, speech.count)])) { segments.append($0) }
        }
        precondition(segments.count == 1 && segments[0].final, "Expected one utterance after a pause")
        let phrase = recognizer.transcribe(segments[0].samples)
        precondition(phrase.lowercased().contains("meeting") && phrase.lowercased().contains("session"), phrase)

        let time = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        var cards = DialogueCards()
        cards.enqueue("[inhales] [BLANK_AUDIO].")
        precondition(cards.text(at: time) == nil)
        cards.enqueue("[BLANK_AUDIO] Good morning [inhales], everyone. (laughter) [Team Alpha] (the second option).")
        precondition(cards.text(at: time) == "Good morning, everyone. [Team Alpha] (the second option).")

        cards = DialogueCards()
        cards.enqueue(phrase)
        precondition(cards.text(at: time) == phrase)
        precondition(cards.text(at: time + .seconds(3)) == nil)
        cards.enqueue(phrase)
        precondition(cards.text(at: time + .seconds(4)) == phrase)

        var preview = PreviewThrottle()
        let firstFrame = DispatchTime.now()
        precondition(preview.allowsFrame(at: firstFrame))
        precondition(!preview.allowsFrame(at: firstFrame + .milliseconds(124)))
        precondition(preview.allowsFrame(at: firstFrame + .milliseconds(125)))

        let source = CameraFormat.allocate(from: CameraFormat.makePool())!
        CVPixelBufferLockBaseAddress(source, [])
        let stride = CVPixelBufferGetBytesPerRow(source) / 4
        let pixels = CVPixelBufferGetBaseAddress(source)!.assumingMemoryBound(to: UInt32.self)
        pixels.initialize(repeating: 0xff1b5bfb, count: stride * CameraFormat.height)
        CVPixelBufferUnlockBaseAddress(source, [])
        let renderer = FilmRenderer()
        let film = renderer.render(source, title: nil)!
        let title = "Please take your seats. The meeting is now in session."
        let card = renderer.render(source, title: title)!
        let nextCard = renderer.render(source, title: title)!
        precondition(CameraFormat.sample(from: film, at: CameraFormat.hostTime) != nil)
        for frame in [film, card] {
            let pixel = pixelAt(x: 300, y: 270, in: frame)
            precondition(abs(Int(pixel.0) - Int(pixel.1)) < 3 && abs(Int(pixel.1) - Int(pixel.2)) < 3)
        }
        precondition(pixelAt(x: 300, y: 270, in: film).0 > 35)
        precondition(pixelAt(x: 300, y: 270, in: card).0 < 25)
        checkCardCenter(card)
        let grain = (280..<328).map { pixelAt(x: $0, y: 250, in: card).0 }
        let nextGrain = (280..<328).map { pixelAt(x: $0, y: 250, in: nextCard).0 }
        precondition(Set(grain).count > 1 && grain != nextGrain, "The card grain should animate")
        #if SILENT_MEETING_LAUNCHER
        try LauncherSmoke.check(frame: film, soundtrack: URL(fileURLWithPath: CommandLine.arguments[3]))
        #endif
        print("Native speech, pause, card cleanup, centering, grain, expiration, preview cadence, monochrome effect, and Core Media sample passed.")
    }

    static func checkCardCenter(_ frame: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(frame)
        for rows in [260..<355, 355..<460] {
            var left = CameraFormat.width
            var right = 0
            for y in rows {
                for x in 110..<(CameraFormat.width - 110) where base[y * stride + x * 4] > 190 {
                    left = min(left, x)
                    right = max(right, x)
                }
            }
            precondition(left < right && abs(left + right + 1 - CameraFormat.width) <= 10,
                         "Expected centered text in rows \(rows), found x=\(left)...\(right)")
        }
    }

    static func pixelAt(x: Int, y: Int, in frame: CVPixelBuffer) -> (UInt8, UInt8, UInt8) {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let pixel = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self) +
                    y * CVPixelBufferGetBytesPerRow(frame) + 4 * x
        return (pixel[0], pixel[1], pixel[2])
    }
}
