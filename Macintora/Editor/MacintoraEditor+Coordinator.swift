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
import os

let editorCompletionLog = Logger(subsystem: "com.iliasazonov.macintora",
                                 category: "editor.completion")

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

        /// Always present once `makeNSView` has run; receives parse-tree
        /// updates from the Neon plugin regardless of whether completion has
        /// been wired yet. The CompletionCoordinator (created lazily once a
        /// non-nil `EditorCompletionConfig` arrives) reads from this same
        /// instance, so tree updates that fire before the coordinator exists
        /// are not lost.
        var treeStore: SQLTreeStore?

        /// Lazily wired when `EditorCompletionConfig` arrives — typically
        /// from `updateNSView` because SwiftUI's `.onAppear` runs the config
        /// constructor AFTER `makeNSView`. Read-only viewers (DBBrowser
        /// source/formatted) leave this nil for the editor's lifetime.
        var completionCoordinator: CompletionCoordinator?

        /// Last UTF-16 cursor location seen in the selection callback. Used to
        /// detect when the cursor moves outside the in-progress identifier so
        /// auto-trigger can be cancelled.
        private var lastCursor: Int = 0

        init(text: Binding<String>, selection: Binding<Range<String.Index>>) {
            self._text = text
            self._selection = selection
        }

        /// Builds the `CompletionCoordinator` using the previously installed
        /// `treeStore`. Idempotent: subsequent calls are no-ops while a
        /// coordinator is already in place.
        @MainActor
        func installCompletionCoordinator(with config: EditorCompletionConfig) {
            guard completionCoordinator == nil else { return }
            guard let treeStore else {
                editorCompletionLog.error("installCompletionCoordinator called before treeStore was set")
                return
            }
            let dataSource = CompletionDataSource(persistenceController: config.persistenceController)
            completionCoordinator = CompletionCoordinator(
                treeStore: treeStore,
                dataSource: dataSource,
                defaultOwnerProvider: config.defaultOwnerProvider)
            editorCompletionLog.info("installCompletionCoordinator: completion wired for editor")
        }

        @MainActor
        func textViewDidChangeText(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? STTextView
            else { return }
            let newText = textView.text ?? ""
            if text != newText {
                text = newText
            }
        }

        /// `didChangeTextIn:replacementString:` is what STTextView calls with
        /// the actual edit payload. Earlier I was capturing it via
        /// `willChangeTextIn:replacementString:`, but my signature used
        /// `String?` while the protocol requires `String`, so Swift never
        /// matched it as a witness and the auto-trigger silently never fired.
        @MainActor
        func textView(_ textView: STTextView,
                      didChangeTextIn affectedCharRange: NSTextRange,
                      replacementString: String) {
            guard !isApplyingExternalUpdate else { return }
            editorCompletionLog.debug("didChangeTextIn replacement=\(replacementString, privacy: .public) coordinator=\(self.completionCoordinator != nil)")
            completionCoordinator?.handleTextChange(textView, replacement: replacementString)
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
