import Foundation

struct DialogueCards {
    private var pages: [String] = []
    private var current: String?
    private var until = DispatchTime(uptimeNanoseconds: 0)

    mutating func enqueue(_ text: String) {
        var page = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if !page.isEmpty && page.count + word.count + 1 > 130 {
                pages.append(page)
                page = ""
            }
            if word.count > 130 {
                if !page.isEmpty { pages.append(page); page = "" }
                var start = word.startIndex
                while start < word.endIndex {
                    let end = word.index(start, offsetBy: 130, limitedBy: word.endIndex) ?? word.endIndex
                    pages.append(String(word[start..<end]))
                    start = end
                }
            } else {
                if !page.isEmpty { page += " " }
                page += word
            }
        }
        if !page.isEmpty { pages.append(page) }
        if pages.count > 8 { pages.removeFirst(pages.count - 8) }
    }

    mutating func text(at now: DispatchTime) -> String? {
        if now >= until {
            current = pages.isEmpty ? nil : pages.removeFirst()
            if let current {
                let ms = min(7_000, max(2_500, current.count * 59))
                until = now + .milliseconds(ms)
            }
        }
        return current
    }
}
