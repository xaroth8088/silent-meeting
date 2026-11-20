import CoreMedia
import Foundation

final class VoiceEndpointer {
    static let rate = 16_000
    static let frameSize = 320
    private static let onsetMask: UInt16 = 0b1_1111
    private static let speechMask: UInt16 = 0x0fff
    private static let pauseFrames = 30

    struct Chunk {
        let utterance: Int
        let samples: [Float]
        let final: Bool
    }

    private let vad: OpaquePointer
    private var pending: [Int16] = []
    private var preRoll: [[Int16]] = []
    private var voiceHistory: UInt16 = 0
    private var active: [Float] = []
    private var started = false
    private var framesSinceSpeech = 0
    private var trailingQuiet = 0
    private var utterance = 0

    init?() {
        guard let vad = fvad_new() else { return nil }
        self.vad = vad
        guard fvad_set_sample_rate(vad, Int32(Self.rate)) == 0, fvad_set_mode(vad, 2) == 0 else {
            fvad_free(vad)
            return nil
        }
    }

    deinit { fvad_free(vad) }

    func discard() {
        preRoll.removeAll(keepingCapacity: true)
        active.removeAll(keepingCapacity: true)
        voiceHistory = 0
        framesSinceSpeech = 0
        trailingQuiet = 0
        started = false
    }

    func append(_ samples: [Int16], emit: (Chunk) -> Void) {
        pending.append(contentsOf: samples)
        var consumed = 0
        while pending.count - consumed >= Self.frameSize {
            let frame = Array(pending[consumed ..< consumed + Self.frameSize])
            consumed += Self.frameSize
            let voiced = frame.withUnsafeBufferPointer { fvad_process(vad, $0.baseAddress, $0.count) } == 1
            if let chunk = process(frame, voiced: voiced) { emit(chunk) }
        }
        if consumed > 0 { pending.removeFirst(consumed) }
    }

    private func process(_ frame: [Int16], voiced: Bool) -> Chunk? {
        voiceHistory = ((voiceHistory << 1) | (voiced ? 1 : 0)) & Self.speechMask
        if !started {
            preRoll.append(frame)
            if preRoll.count > 8 { preRoll.removeFirst() }
            guard voiced, (voiceHistory & Self.onsetMask).nonzeroBitCount >= 3 else { return nil }
            for saved in preRoll { active.append(contentsOf: saved.map { Float($0) / 32_768 }) }
            preRoll.removeAll(keepingCapacity: true)
            started = true
            utterance += 1
            return nil
        }

        active.append(contentsOf: frame.map { Float($0) / 32_768 })
        // Brief VAD positives, plus its own hangover, can occur during a real pause.
        // Reset the deadline only with sustained voice in the last 240 ms.
        let sustained = voiced && voiceHistory.nonzeroBitCount >= 10
        framesSinceSpeech = sustained ? 0 : framesSinceSpeech + 1
        trailingQuiet = voiced ? 0 : trailingQuiet + 1
        if framesSinceSpeech >= Self.pauseFrames && trailingQuiet > 0 {
            // Keep brief sounds in the audio in case a short word was spoken.
            let trim = max(0, trailingQuiet - 8) * Self.frameSize
            let ending = active.dropLast(min(active.count, trim))
            let chunk = Chunk(utterance: utterance, samples: Array(ending), final: true)
            discard()
            return chunk
        }
        if voiced && active.count >= 20 * Self.rate {
            let chunk = Chunk(utterance: utterance, samples: active, final: false)
            active.removeAll()
            return chunk
        }
        return nil
    }
}

final class WhisperRecognizer {
    private let context: OpaquePointer

    init?(model: URL) {
        var options = whisper_context_default_params()
        options.use_gpu = false
        guard let context = model.path.withCString({ whisper_init_from_file_with_params($0, options) }) else { return nil }
        self.context = context
    }

    deinit { whisper_free(context) }

    func transcribe(_ samples: [Float]) -> String {
        guard samples.count >= VoiceEndpointer.rate / 10 else { return "" }
        var options = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        options.n_threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
        options.print_progress = false
        options.print_realtime = false
        options.print_timestamps = false
        options.no_context = true
        options.no_timestamps = true
        let status = "auto".withCString { language in
            options.language = language
            return samples.withUnsafeBufferPointer { whisper_full(context, options, $0.baseAddress, Int32($0.count)) }
        }
        guard status == 0 else { return "" }
        return (0 ..< whisper_full_n_segments(context))
            .compactMap { whisper_full_get_segment_text(context, $0) }
            .map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

final class SpeechPipeline {
    private let endpointer: VoiceEndpointer
    private let recognizer: WhisperRecognizer
    private let inference = DispatchQueue(label: "Silent Meeting speech recognition", qos: .userInitiated)
    private let slots = DispatchSemaphore(value: 5)
    private var currentUtterance = 0
    private var parts: [String] = []
    private let publish: (String) -> Void

    init?(model: URL, publish: @escaping (String) -> Void) {
        guard let endpointer = VoiceEndpointer(), let recognizer = WhisperRecognizer(model: model) else { return nil }
        self.endpointer = endpointer
        self.recognizer = recognizer
        self.publish = publish
    }

    func append(_ sample: CMSampleBuffer) {
        guard let format = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mSampleRate == 16_000,
              asbd.mChannelsPerFrame == 1, asbd.mBitsPerChannel == 16,
              asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
              let block = sample.dataBuffer else { return }

        let length = CMBlockBufferGetDataLength(block)
        guard length > 0, length % 2 == 0 else { return }
        var samples = [Int16](repeating: 0, count: length / 2)
        let status = samples.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
        }
        guard status == noErr else { return }
        endpointer.append(samples) { [self] chunk in
            guard slots.wait(timeout: .now()) == .success else {
                endpointer.discard()
                return
            }
            inference.async {
                defer { self.slots.signal() }
                if self.currentUtterance != chunk.utterance {
                    self.currentUtterance = chunk.utterance
                    self.parts.removeAll()
                }
                let text = self.recognizer.transcribe(chunk.samples)
                if !text.isEmpty {
                    self.parts.append(text)
                    if self.parts.count > 12 { self.parts.removeFirst() }
                }
                if chunk.final {
                    self.publish(self.parts.joined(separator: " "))
                    self.parts.removeAll()
                }
            }
        }
    }
}
