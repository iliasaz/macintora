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

        /// Quick View orchestrator — owned alongside `completionCoordinator`
        /// so both share the same `treeStore` and `dataSource`. nil for
        /// read-only viewers that opt out of completion.
        var quickViewController: QuickViewController?

        /// Weak reference back to the SwiftUI-owned Quick View box so we can
        /// detect identity changes (rebind on full document re-init).
        weak var quickViewBoxRef: EditorQuickViewBox?

        /// Weak reference back to the SwiftUI-owned Open-in-Browser box so we
        /// can detect identity changes and avoid double-binding.
        weak var openInBrowserBoxRef: EditorOpenInBrowserBox?

        /// Weak reference back to the SwiftUI-owned Toggle Line Comment box.
        weak var toggleCommentBoxRef: EditorToggleCommentBox?

        /// Last UTF-16 cursor location seen in the selection callback. Used to
        /// detect when the cursor moves outside the in-progress identifier so
        /// auto-trigger can be cancelled.
        private var lastCursor: Int = 0

        /// Range currently carrying the transient "you jumped here" highlight,
        /// applied via rendering attributes (draw-time only — doesn't touch the
        /// text storage, so it doesn't fight the Neon highlighter). `nil` when
        /// nothing is flashed.
        private var navigationHighlightRange: NSRange?
        private var navigationHighlightClearTask: Task<Void, Never>?

        /// Last `revealGeneration` value observed from the SwiftUI side. Set
        /// from `updateNSView`; used to detect host-requested reveals that
        /// shouldn't be skipped just because `selection` didn't change.
        var lastRevealGeneration: Int = 0

        init(text: Binding<String>, selection: Binding<Range<String.Index>>) {
            self._text = text
            self._selection = selection
        }

        /// Briefly tints `range` (typically the source line a programmatic jump
        /// landed on — code-outline navigation, Script Output's "reveal in
        /// editor") with the system find/search-results colour so it's easy to
        /// spot, then clears it. Out-of-bounds ranges are no-ops (STTextView's
        /// rendering-attribute API ignores them).
        @MainActor
        func flashNavigationHighlight(_ range: NSRange, in textView: STTextView) {
            navigationHighlightClearTask?.cancel()
            if let previous = navigationHighlightRange {
                textView.removeRenderingAttribute(.backgroundColor, range: previous)
                navigationHighlightRange = nil
            }
            guard range.length > 0 else { return }
            textView.addRenderingAttributes([.backgroundColor: NSColor.findHighlightColor], range: range)
            navigationHighlightRange = range
            navigationHighlightClearTask = Task { [weak self, weak textView] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, let self, let textView else { return }
                if let lit = self.navigationHighlightRange {
                    textView.removeRenderingAttribute(.backgroundColor, range: lit)
                    self.navigationHighlightRange = nil
                }
            }
        }

        /// Builds the `CompletionCoordinator` using the previously installed
        /// `treeStore`. Idempotent: subsequent calls are no-ops while a
        /// coordinator is already in place. Returns the coordinator on first
        /// build so the caller can install dependent plugins.
        @MainActor
        @discardableResult
        func installCompletionCoordinator(with config: EditorCompletionConfig) -> CompletionCoordinator? {
            if let completionCoordinator { return completionCoordinator }
            guard let treeStore else {
                editorCompletionLog.error("installCompletionCoordinator called before treeStore was set")
                return nil
            }
            let dataSource = CompletionDataSource(persistenceController: config.persistenceController)
            let coordinator = CompletionCoordinator(
                treeStore: treeStore,
                dataSource: dataSource,
                defaultOwnerProvider: config.defaultOwnerProvider)
            completionCoordinator = coordinator
            editorCompletionLog.info("installCompletionCoordinator: completion wired for editor")
            return coordinator
        }

        /// Builds the Quick View controller once the `completionCoordinator`
        /// has been installed. Re-uses its `treeStore` and `dataSource`.
        @MainActor
        func installQuickViewController(textView: STTextView) {
            guard quickViewController == nil,
                  let completionCoordinator else { return }
            quickViewController = QuickViewController(
                textView: textView,
                treeStore: completionCoordinator.treeStore,
                dataSource: completionCoordinator.dataSource,
                defaultOwnerProvider: completionCoordinator.defaultOwnerProvider)
        }

        /// Wires the SwiftUI-owned `EditorQuickViewBox` to this editor's
        /// Quick View controller. The box's `trigger` closure becomes the
        /// path the menu command uses to invoke Quick View at the cursor.
        @MainActor
        func bindQuickViewBox(_ box: EditorQuickViewBox?, textView: STTextView) {
            // Drop the previous box's trigger so a stale closure doesn't
            // keep us alive after a re-mount.
            quickViewBoxRef?.trigger = nil
            quickViewBoxRef = box
            guard let box, let controller = quickViewController else { return }
            box.trigger = { [weak controller, weak textView] in
                guard let controller, let textView else { return }
                controller.triggerAtCursor(textView: textView)
            }
        }

        /// Sets `quickViewController.openInBrowserHandler` to a closure that maps
        /// the resolved reference to a `DBCacheInputValue` and routes through
        /// `openOrFocusDBBrowser`. Clears the handler when `mainConnectionProvider`
        /// is nil (read-only viewer has no connection).
        @MainActor
        func wireOpenInBrowserHandler(
            openWindow: OpenWindowAction,
            mainConnectionProvider: (@MainActor () -> MainConnection?)?
        ) {
            guard let controller = quickViewController else { return }
            guard let mainConnectionProvider else {
                controller.openInBrowserHandler = nil
                return
            }
            controller.openInBrowserHandler = { [weak controller] reference in
                guard controller != nil else { return }
                guard let connection = mainConnectionProvider() else { return }
                let value = DBBrowserInputMapper.inputValue(from: reference,
                                                            mainConnection: connection)
                openOrFocusDBBrowser(value: value, openWindow: openWindow)
            }
        }

        /// Wires the SwiftUI-owned `EditorOpenInBrowserBox` to this editor's
        /// Quick View controller. The box's `trigger` closure is the path
        /// the ⌥⌘B menu command uses to open the browser at the cursor.
        @MainActor
        func bindOpenInBrowserBox(_ box: EditorOpenInBrowserBox?, textView: STTextView) {
            openInBrowserBoxRef?.trigger = nil
            openInBrowserBoxRef = box
            guard let box, let controller = quickViewController else { return }
            box.trigger = { [weak controller, weak textView] in
                guard let controller, let textView else { return }
                controller.openInBrowserAtCursor(textView: textView)
            }
        }

        /// Wires the SwiftUI-owned `EditorToggleCommentBox` to this editor's
        /// text view. The box's `trigger` becomes the path the ⌘/ menu
        /// command uses to call `MacintoraSTTextView.toggleLineComment`.
        @MainActor
        func bindToggleCommentBox(_ box: EditorToggleCommentBox?, textView: STTextView) {
            toggleCommentBoxRef?.trigger = nil
            toggleCommentBoxRef = box
            guard let box else { return }
            box.trigger = { [weak textView] in
                guard let textView = textView as? MacintoraSTTextView else { return }
                textView.toggleLineComment(nil)
            }
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
