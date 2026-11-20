import CoreMedia
import Foundation

final class VoiceEndpointer {
    static let rate = 16_000
    static let frameSize = 320

    struct Chunk {
        let utterance: Int
        let samples: [Float]
        let final: Bool
    }

    private let vad: OpaquePointer
    private var pending: [Int16] = []
    private var preRoll: [[Int16]] = []
    private var votes: [Bool] = []
    private var active: [Float] = []
    private var started = false
    private var quiet = 0
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
        votes.removeAll(keepingCapacity: true)
        active.removeAll(keepingCapacity: true)
        quiet = 0
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
        if !started {
            preRoll.append(frame)
            if preRoll.count > 8 { preRoll.removeFirst() }
            votes.append(voiced)
            if votes.count > 5 { votes.removeFirst() }
            guard voiced, votes.filter({ $0 }).count >= 3 else { return nil }
            for saved in preRoll { active.append(contentsOf: saved.map { Float($0) / 32_768 }) }
            preRoll.removeAll(keepingCapacity: true)
            votes.removeAll(keepingCapacity: true)
            started = true
            utterance += 1
            return nil
        }

        active.append(contentsOf: frame.map { Float($0) / 32_768 })
        quiet = voiced ? 0 : quiet + 1
        if quiet >= 38 {
            let ending = active.dropLast(min(active.count, (quiet - 8) * Self.frameSize))
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
