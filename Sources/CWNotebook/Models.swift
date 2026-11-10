import Foundation

/// A note is a plain text file. Its first line is its title, as in Apple Notes.
struct Note: Identifiable, Hashable {
    /// File name without the `.md` extension.
    let id: String
    var text: String
    var modified: Date
    /// Folder the note lives in (or came from, for a note in the Trash); nil = unfiled.
    var folder: String? = nil

    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var title: String {
        guard let first = lines.first else { return "New Note" }
        let t = first.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        return t.isEmpty ? "New Note" : String(t.prefix(80))
    }

    /// File layout: "# TITLE", a blank line, then the body. A first line without "#" is
    /// still treated as the title, so plain text files written elsewhere work too.
    static func split(_ text: String) -> (title: String, body: String) {
        guard !text.isEmpty else { return ("", "") }
        let firstBreak = text.firstIndex(of: "\n") ?? text.endIndex
        var title = String(text[..<firstBreak]).trimmingCharacters(in: .whitespaces)
        if title.hasPrefix("#") {
            title = String(title.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
        var body = firstBreak < text.endIndex ? String(text[text.index(after: firstBreak)...]) : ""
        if body.hasPrefix("\n") { body.removeFirst() }
        return (title, body)
    }

    static func join(title: String, body: String) -> String {
        if title.isEmpty && body.isEmpty { return "" }
        return "# \(title)\n\n\(body)"
    }

    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func matches(_ query: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }
}

extension Date {
    /// "2026-11-10 2003Z", the usual way to write a time on the air.
    static let utcStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "yyyy-MM-dd HHmm'Z'"
        return f
    }()

    var utcStamp: String { Date.utcStampFormatter.string(from: self) }

    /// "20:31:05Z" for the toolbar clock.
    static let utcClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "HH:mm:ss'Z'"
        return f
    }()
}
