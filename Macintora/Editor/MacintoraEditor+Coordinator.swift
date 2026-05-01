//
//  MacintoraEditor+Coordinator.swift
//  Macintora
//
//  Delegate bridge between `STTextView` (AppKit, NSRange) and `MacintoraEditor`'s
//  SwiftUI bindings (`String` + `Range<String.Index>`). Kept in its own file so
//  the delegate surface is easy to audit.
//

import AppKit
import SwiftUI
import STTextView

extension MacintoraEditorRepresentable {
    /// `STTextViewDelegate` predates Swift Concurrency and isn't annotated, so
    /// its protocol requirements are nonisolated. AppKit always invokes these
    /// callbacks on the main thread, so the `STTextView` reads inside are
    /// scoped with `MainActor.assumeIsolated { }` — that gives the compiler
    /// the main-actor access it needs while keeping the witness nonisolated.
    final class Coordinator: NSObject, @MainActor STTextViewDelegate {
        @Binding var text: String
        @Binding var selection: Range<String.Index>

        /// Raised while `updateNSView` is pushing SwiftUI state into the view so
        /// the delegate callbacks can distinguish "user typed" from "binding changed".
        var isApplyingExternalUpdate = false

        /// Raised while `textViewDidChangeSelection` is writing into the binding
        /// to prevent `updateNSView` from immediately writing the same value back.
        var isPushingSelection = false

        /// Optional. Wired only when the editor is configured with a
        /// `EditorCompletionConfig` (worksheet); read-only viewers leave this nil.
        var completionCoordinator: CompletionCoordinator?

        /// Last UTF-16 cursor location seen in the selection callback. Used to
        /// detect when the cursor moves outside the in-progress identifier so
        /// auto-trigger can be cancelled.
        private var lastCursor: Int = 0

        init(text: Binding<String>, selection: Binding<Range<String.Index>>) {
            self._text = text
            self._selection = selection
        }

        @MainActor
        func textView(_ textView: STTextView, willChangeTextIn affectedCharRange: NSTextRange, replacementString: String?) {
            // Capture the replacement string here so we can decide whether to
            // auto-trigger after the change applies. STTextViewDelegate's
            // didChange notification doesn't carry it.
            pendingReplacement = replacementString
        }

        private var pendingReplacement: String?

        @MainActor
        func textViewDidChangeText(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? STTextView
            else { return }
            let newText = textView.text ?? ""
            if text != newText {
                text = newText
            }
            // Auto-trigger evaluation runs on every text change. The
            // coordinator decides whether the keystroke warrants popping the
            // completion menu and debounces accordingly.
            if let replacement = pendingReplacement {
                pendingReplacement = nil
                completionCoordinator?.handleTextChange(textView, replacement: replacement)
            }
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? STTextView
            else { return }
            // Read the upstream text from the view, not the binding: the binding may
            // still be catching up after a keystroke, which would leave the NSRange
            // out of bounds for the old value.
            let nsRange = textView.selectedRange()
            let source = textView.text ?? ""
            let bridged = EditorSelectionBridge.range(for: nsRange, in: source)
                ?? EditorSelectionBridge.emptyRange(in: source)
            if bridged != selection {
                isPushingSelection = true
                selection = bridged
                isPushingSelection = false
            }
            // Cancel any pending auto-trigger when the cursor jumps. Without
            // this the popup can fire after the user has clicked elsewhere.
            if abs(nsRange.location - lastCursor) > 1 {
                completionCoordinator?.cancelPending()
            }
            lastCursor = nsRange.location
        }
    }
}
