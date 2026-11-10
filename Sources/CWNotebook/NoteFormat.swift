import Foundation

/// Bold, italic and underline, stored in the note file as Markdown:
/// `**bold**`, `*italic*`, `<u>underline</u>`. Literal `*`, `<` and `\` are escaped
/// with a backslash. Formatting never spans a line break.
enum NoteFormat {
    struct Style: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var isPlain: Bool { !bold && !italic && !underline }
    }

    typealias Run = (text: String, style: Style)

    // MARK: Markdown → runs

    static func parse(_ markdown: String) -> [Run] {
        var runs: [Run] = []
        var style = Style()
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            if let last = runs.last, last.style == style { runs[runs.count - 1].text += buffer }
            else { runs.append((buffer, style)) }
            buffer = ""
        }
        let chars = Array(markdown)
        var i = 0
        func matches(_ token: String) -> Bool {
            let t = Array(token)
            return i + t.count <= chars.count && Array(chars[i..<i + t.count]) == t
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, "\\*<".contains(chars[i + 1]) {
                buffer.append(chars[i + 1]); i += 2
            } else if c == "\n" {
                flush(); style = Style(); buffer.append(c); i += 1
            } else if matches("**") {
                flush(); style.bold.toggle(); i += 2
            } else if c == "*" {
                flush(); style.italic.toggle(); i += 1
            } else if matches("<u>") {
                flush(); style.underline = true; i += 3
            } else if matches("</u>") {
                flush(); style.underline = false; i += 4
            } else {
                buffer.append(c); i += 1
            }
        }
        flush()
        return runs
    }

    static func plain(_ markdown: String) -> String {
        parse(markdown).map(\.text).joined()
    }

    // MARK: Runs → Markdown

    static func serialize(_ runs: [Run]) -> String {
        var out = ""
        for run in runs {
            let lines = run.text.components(separatedBy: "\n")
            for (n, line) in lines.enumerated() {
                if n > 0 { out += "\n" }
                out += wrap(line, run.style)
            }
        }
        return out
    }

    /// Markers go inside any leading/trailing spaces so the Markdown stays valid.
    private static func wrap(_ segment: String, _ style: Style) -> String {
        let core = segment.trimmingCharacters(in: .whitespaces)
        guard !style.isPlain, !core.isEmpty else { return escape(segment) }
        let lead = String(segment.prefix { $0 == " " || $0 == "\t" })
        let trail = String(segment.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        var open = "", close = ""
        if style.underline { open += "<u>"; close = "</u>" + close }
        if style.bold { open += "**"; close = "**" + close }
        if style.italic { open += "*"; close = "*" + close }
        return lead + open + escape(core) + close + trail
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "<", with: "\\<")
    }
}
