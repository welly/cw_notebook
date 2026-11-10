import AppKit
import SwiftUI

/// A bare NSTextView: no predictions, autocorrect, completion, spell check, smart
/// punctuation or Writing Tools. Upper-cases everything typed or pasted,
/// so you get capitals without Caps Lock (and without its on-screen ⇪ indicator).
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var monospaced: Bool
    var focusOnAppear = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true

        Self.quieten(tv)

        tv.textContainerInset = NSSize(width: 16, height: 14)
        tv.backgroundColor = .textBackgroundColor
        tv.string = text
        context.coordinator.textView = tv
        applyFont(to: tv)
        if focusOnAppear { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text { tv.string = text }
        applyFont(to: tv)
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

    private func applyFont(to tv: NSTextView) {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            : NSFont.systemFont(ofSize: 15)
        guard tv.font != font else { return }
        tv.font = font
        tv.typingAttributes[.font] = font
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        weak var textView: NSTextView?
        private var observer: NSObjectProtocol?
        private var focusObserver: NSObjectProtocol?

        init(_ parent: PlainTextEditor) {
            self.parent = parent
            super.init()
            observer = NotificationCenter.default.addObserver(forName: .insertText, object: nil, queue: .main) { [weak self] n in
                guard let s = n.object as? String, let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.insertText(s, replacementRange: tv.selectedRange())
            }
            focusObserver = NotificationCenter.default.addObserver(forName: .focusBody, object: nil, queue: .main) { [weak self] _ in
                guard let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
            }
        }

        deinit {
            for o in [observer, focusObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(o) }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString s: String?) -> Bool {
            guard let s, !tv.hasMarkedText() else { return true }
            let upper = s.uppercased()
            guard upper != s else { return true }
            // Re-insert in capitals; this re-enters here with an unchanged string and goes through.
            tv.insertText(upper, replacementRange: range)
            return false
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
