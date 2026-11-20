import NaturalLanguage
import os

enum SoundtrackMood: String, CaseIterable, Sendable {
    case neutral = "maple-leaf-rag"
    case upbeat = "the-entertainer"
    case somber = "gymnopedie-no-1"

    init?(score: Double) {
        guard (-1.0...1.0).contains(score) else { return nil }
        if score >= 0.8 {
            self = .upbeat
        } else if score <= -0.9 {
            self = .somber
        } else {
            self = .neutral
        }
    }
}

final class SoundtrackCue: Sendable {
    let mood = OSAllocatedUnfairLock<SoundtrackMood?>(initialState: nil)
}

final class SoundtrackSentiment {
    private let queue = DispatchQueue(label: "Silent Meeting sentiment", qos: .userInitiated)
    private lazy var tagger = NLTagger(tagSchemes: [.sentimentScore])

    init() {
        queue.async { [self] in
            _ = classify("The meeting is now in session.")
        }
    }

    func prepare(_ text: String) -> SoundtrackCue {
        let cue = SoundtrackCue()
        queue.async { [self, weak cue] in
            guard let cue else { return }
            let result = classify(text)
            cue.mood.withLock { $0 = result }
        }
        return cue
    }

    private func classify(_ text: String) -> SoundtrackMood? {
        tagger.string = text
        defer { tagger.string = nil }
        let tag = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore).0
        guard let tag, let score = Double(tag.rawValue) else { return nil }
        return SoundtrackMood(score: score)
    }
}
