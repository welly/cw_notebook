import Foundation

/// A note is a plain text file. Its first line is its title, as in Apple Notes.
struct Note: Identifiable, Hashable {
    /// File name without the `.md` extension.
    let id: String
    var text: String
    var modified: Date

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

    var preview: String {
        lines.dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
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
}
