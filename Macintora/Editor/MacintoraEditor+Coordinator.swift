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

extension MacintoraEditor {
    /// `STTextViewDelegate` predates Swift Concurrency and isn't annotated;
    /// the methods touch `@MainActor`-isolated `STTextView` API at runtime
    /// (always called on main by AppKit) but the protocol witness is treated
    /// as nonisolated, so Swift 6.2 emits warnings about each main-actor
    /// access. The combinations that actually compile under approachable
    /// concurrency leave at least one of those warnings — `@preconcurrency`,
    /// `@MainActor`-on-class, and `@MainActor`-on-method all conflict with
    /// the nonisolated protocol requirement. Leaving the warnings in place
    /// with this comment documents the upstream limitation. Drop the warnings
    /// when STTextView adopts Swift Concurrency.
    final class Coordinator: NSObject, @preconcurrency STTextViewDelegate {
        @Binding var text: String
        @Binding var selection: Range<String.Index>

        /// Raised while `updateNSView` is pushing SwiftUI state into the view so
        /// the delegate callbacks can distinguish "user typed" from "binding changed".
        var isApplyingExternalUpdate = false

        /// Raised while `textViewDidChangeSelection` is writing into the binding
        /// to prevent `updateNSView` from immediately writing the same value back.
        var isPushingSelection = false

        init(text: Binding<String>, selection: Binding<Range<String.Index>>) {
            self._text = text
            self._selection = selection
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? STTextView
            else { return }
            let newText = textView.text ?? ""
            if text != newText {
                text = newText
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? STTextView
            else { return }
            let nsRange = textView.selectedRange()
            // Read the upstream text from the view, not the binding: the binding may
            // still be catching up after a keystroke, which would leave the NSRange
            // out of bounds for the old value.
            let source = textView.text ?? ""
            let bridged = EditorSelectionBridge.range(for: nsRange, in: source)
                ?? EditorSelectionBridge.emptyRange(in: source)
            if bridged != selection {
                isPushingSelection = true
                selection = bridged
                isPushingSelection = false
            }
        }
    }
}
