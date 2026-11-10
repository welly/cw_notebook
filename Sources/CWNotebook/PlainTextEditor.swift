import AppKit
import SwiftUI

/// A bare NSTextView: no predictions, autocorrect, completion, spell check, smart
/// punctuation or Writing Tools. Upper-cases everything typed or pasted,
/// so you get capitals without Caps Lock (and without its on-screen ⇪ indicator).
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var monospaced: Bool

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

        // Everything that second-guesses what you type: off.
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

        tv.textContainerInset = NSSize(width: 16, height: 14)
        tv.backgroundColor = .textBackgroundColor
        tv.string = text
        context.coordinator.textView = tv
        applyFont(to: tv)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text { tv.string = text }
        applyFont(to: tv)
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

        init(_ parent: PlainTextEditor) {
            self.parent = parent
            super.init()
            observer = NotificationCenter.default.addObserver(forName: .insertText, object: nil, queue: .main) { [weak self] n in
                guard let s = n.object as? String, let tv = self?.textView else { return }
                tv.window?.makeFirstResponder(tv)
                tv.insertText(s, replacementRange: tv.selectedRange())
            }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

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
