import Foundation

struct DialogueCards {
    struct Page {
        let text: String
        let cue: SoundtrackCue?
    }

    private static let soundMarker: String = {
        let gap = #"[\s_-]+"#
        let cue = [
            "blank\(gap)audio", "no\(gap)speech", "silence", "inaudible", "unintelligible",
            "inhal(?:e[sd]?|ing)", "exhal(?:e[sd]?|ing)", "breath(?:s|ing)?",
            "sigh(?:s|ed|ing)?", "cough(?:s|ed|ing)?", "sniff(?:s|ed|ing)?",
            "laugh(?:s|ed|ing|ter)?", "chuckl(?:e[sd]?|ing)", "applause",
            "clears?\(gap)(?:their\(gap))?throat", "throat\(gap)clearing",
            "(?:background\(gap))?(?:music|noise)",
        ].joined(separator: "|")
        return "\\[\\s*(?:\(cue))\\s*\\]|\\(\\s*(?:\(cue))\\s*\\)"
    }()

    private var pages: [Page] = []
    private var current: Page?
    private var until = DispatchTime(uptimeNanoseconds: 0)

    static func prepare(_ text: String, sentiment: SoundtrackSentiment? = nil) -> Page? {
        let stripped = text.replacingOccurrences(of: Self.soundMarker, with: " ",
                                                 options: [.regularExpression, .caseInsensitive])
        let dialogue: String
        if stripped == text {
            dialogue = text
        } else {
            guard stripped.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            dialogue = stripped.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1",
                                                     options: .regularExpression)
        }
        let clean = dialogue.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        return Page(text: clean, cue: sentiment?.prepare(clean))
    }

    mutating func enqueue(_ transcript: Page) {
        var page = ""
        for word in transcript.text.split(separator: " ") {
            if !page.isEmpty && page.count + word.count + 1 > 130 {
                pages.append(Page(text: page, cue: transcript.cue))
                page = ""
            }
            if word.count > 130 {
                var start = word.startIndex
                while start < word.endIndex {
                    let end = word.index(start, offsetBy: 130, limitedBy: word.endIndex) ?? word.endIndex
                    pages.append(Page(text: String(word[start..<end]), cue: transcript.cue))
                    start = end
                }
            } else {
                if !page.isEmpty { page += " " }
                page += word
            }
        }
        if !page.isEmpty { pages.append(Page(text: page, cue: transcript.cue)) }
        if pages.count > 8 { pages.removeFirst(pages.count - 8) }
    }

    mutating func page(at now: DispatchTime) -> Page? {
        if now >= until {
            current = pages.isEmpty ? nil : pages.removeFirst()
            if let current {
                let ms = min(7_000, max(2_500, current.text.count * 59))
                until = now + .milliseconds(ms)
            }
        }
        return current
    }
}
