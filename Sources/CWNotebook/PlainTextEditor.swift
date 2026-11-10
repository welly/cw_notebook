import AppKit
import SwiftUI

extension NSAttributedString.Key {
    static let cwBold = NSAttributedString.Key("CWNotebookBold")
    static let cwItalic = NSAttributedString.Key("CWNotebookItalic")
}

/// Maps NoteFormat styles to text attributes and back.
enum FormatAttributes {
    static let size: CGFloat = 15

    static func style(_ a: [NSAttributedString.Key: Any]) -> NoteFormat.Style {
        NoteFormat.Style(bold: a[.cwBold] != nil,
                         italic: a[.cwItalic] != nil,
                         underline: ((a[.underlineStyle] as? Int) ?? 0) != 0)
    }

    static func attributes(_ s: NoteFormat.Style, monospaced: Bool) -> [NSAttributedString.Key: Any] {
        let weight: NSFont.Weight = s.bold ? .bold : .regular
        var font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                              : NSFont.systemFont(ofSize: size, weight: weight)
        var oblique = false
        if s.italic {
            let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            if let f = NSFont(descriptor: d, size: size), f.fontDescriptor.symbolicTraits.contains(.italic) {
                font = f
            } else {
                oblique = true // no true italic for this face: slant it instead
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        if s.bold { a[.cwBold] = true }
        if s.italic { a[.cwItalic] = true }
        if s.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if oblique { a[.obliqueness] = 0.18 }
        return a
    }

    static func attributed(_ markdown: String, monospaced: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in NoteFormat.parse(markdown) {
            out.append(NSAttributedString(string: run.text, attributes: attributes(run.style, monospaced: monospaced)))
        }
        return out
    }

    static func markdown(_ a: NSAttributedString) -> String {
        NoteFormat.serialize(runs(a).map { (a.attributedSubstring(from: $0.range).string, $0.style) })
    }

    static func runs(_ a: NSAttributedString, in range: NSRange? = nil) -> [(range: NSRange, style: NoteFormat.Style)] {
        var result: [(NSRange, NoteFormat.Style)] = []
        a.enumerateAttributes(in: range ?? NSRange(location: 0, length: a.length)) { attrs, r, _ in
            result.append((r, style(attrs)))
        }
        return result
    }

    /// Re-applies fonts for every run (after switching monospaced on or off).
    static func restyle(_ storage: NSTextStorage, monospaced: Bool) {
        storage.beginEditing()
        for run in runs(storage) { storage.setAttributes(attributes(run.style, monospaced: monospaced), range: run.range) }
        storage.endEditing()
    }
}

/// Pastes and drops arrive as plain text, so outside formatting never comes in.
final class NoteTextView: NSTextView {
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

/// The note body: an NSTextView with no predictions, autocorrect, completion, spell
/// check, smart punctuation or Writing Tools. Upper-cases everything typed or pasted,
/// so you get capitals without Caps Lock (and without its on-screen ⇪ indicator).
/// Supports bold, italic and underline, bound to the note as Markdown.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var monospaced: Bool
    var focusOnAppear = true
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let tv = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = tv

        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isEditable = editable
        Self.quieten(tv)

        tv.textContainerInset = NSSize(width: 16, height: 14)
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.insertionPointColor = .textColor

        context.coordinator.textView = tv
        context.coordinator.load(text, monospaced: monospaced)
        if focusOnAppear && editable { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView, let storage = tv.textStorage else { return }
        if text != c.lastMarkdown {
            c.load(text, monospaced: monospaced)
        } else if c.lastMonospaced != monospaced {
            FormatAttributes.restyle(storage, monospaced: monospaced)
            tv.typingAttributes = FormatAttributes.attributes(FormatAttributes.style(tv.typingAttributes), monospaced: monospaced)
            c.lastMonospaced = monospaced
        }
    }

    /// Everything that second-guesses what you type: off.
    static func quieten(_ tv: NSTextView) {
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.inlinePredictionType = .no
        if #available(macOS 15.1, *) { tv.writingToolsBehavior = .none }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        weak var textView: NSTextView?
        var lastMarkdown = ""
        var lastMonospaced = true
        private var observers: [NSObjectProtocol] = []

        init(_ parent: PlainTextEditor) {
            self.parent = parent
            super.init()
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: .insertText, object: nil, queue: .main) { [weak self] n in
                guard let s = n.object as? String, let tv = self?.textView, tv.isEditable else { return }
                tv.window?.makeFirstResponder(tv)
                tv.insertText(s, replacementRange: tv.selectedRange())
            })
            observers.append(nc.addObserver(forName: .focusBody, object: nil, queue: .main) { [weak self] _ in
                guard let tv = self?.textView, tv.isEditable else { return }
                tv.window?.makeFirstResponder(tv)
            })
            observers.append(nc.addObserver(forName: .toggleFormat, object: nil, queue: .main) { [weak self] n in
                guard let which = n.object as? FormatCommand else { return }
                self?.toggle(which)
            })
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func load(_ markdown: String, monospaced: Bool) {
            guard let tv = textView else { return }
            tv.textStorage?.setAttributedString(FormatAttributes.attributed(markdown, monospaced: monospaced))
            tv.typingAttributes = FormatAttributes.attributes(.init(), monospaced: monospaced)
            lastMarkdown = markdown
            lastMonospaced = monospaced
        }

        func textDidChange(_ notification: Notification) {
            guard let storage = textView?.textStorage else { return }
            lastMarkdown = FormatAttributes.markdown(storage)
            parent.text = lastMarkdown
        }

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString s: String?) -> Bool {
            guard let s, !tv.hasMarkedText() else { return true }
            let upper = s.uppercased()
            guard upper != s else { return true }
            // Re-insert in capitals; this re-enters here with an unchanged string and goes through.
            tv.insertText(upper, replacementRange: range)
            return false
        }

        /// ⌘B / ⌘I / ⌘U: toggles the selection, or what you type next if nothing is selected.
        func toggle(_ which: FormatCommand) {
            guard let tv = textView, tv.isEditable, tv.window?.firstResponder === tv,
                  let storage = tv.textStorage else { return }
            let key = which.keyPath
            let mono = parent.monospaced
            let range = tv.selectedRange()

            if range.length == 0 {
                var s = FormatAttributes.style(tv.typingAttributes)
                s[keyPath: key].toggle()
                tv.typingAttributes = FormatAttributes.attributes(s, monospaced: mono)
                return
            }

            let runs = FormatAttributes.runs(storage, in: range)
            let turnOn = !runs.allSatisfy { $0.style[keyPath: key] }
            guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            for run in runs {
                var s = run.style
                s[keyPath: key] = turnOn
                storage.setAttributes(FormatAttributes.attributes(s, monospaced: mono), range: run.range)
            }
            storage.endEditing()
            tv.didChangeText()
            var typing = FormatAttributes.style(tv.typingAttributes)
            typing[keyPath: key] = turnOn
            tv.typingAttributes = FormatAttributes.attributes(typing, monospaced: mono)
        }
    }
}

enum FormatCommand {
    case bold, italic, underline
    var keyPath: WritableKeyPath<NoteFormat.Style, Bool> {
        switch self {
        case .bold: \.bold
        case .italic: \.italic
        case .underline: \.underline
        }
    }
}

/// While the title is being edited AppKit uses a shared NSTextView ("field editor");
/// switch its predictions and corrections off each time it takes over.
final class QuietTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView { PlainTextEditor.quieten(editor) }
        return ok
    }
}

/// Single-line counterpart for the note title: no predictions, normal case.
/// Return or Tab moves to the body.
struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var monospaced: Bool
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = QuietTextField()
        tf.delegate = context.coordinator
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.lineBreakMode = .byTruncatingTail
        tf.cell?.usesSingleLineMode = true
        tf.placeholderString = placeholder
        tf.isAutomaticTextCompletionEnabled = false
        tf.stringValue = text
        tf.setContentHuggingPriority(.defaultHigh, for: .vertical)
        applyFont(to: tf)
        if focusOnAppear { DispatchQueue.main.async { tf.window?.makeFirstResponder(tf) } }
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        if tf.stringValue != text, tf.currentEditor() == nil { tf.stringValue = text }
        applyFont(to: tf)
    }

    private func applyFont(to tf: NSTextField) {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
            : NSFont.systemFont(ofSize: 20, weight: .semibold)
        if tf.font != font { tf.font = font }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainTextField
        init(_ parent: PlainTextField) { self.parent = parent }

        func controlTextDidChange(_ n: Notification) {
            guard let tf = n.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) {
                NotificationCenter.default.post(name: .focusBody, object: nil)
                return true
            }
            return false
        }
    }
}
