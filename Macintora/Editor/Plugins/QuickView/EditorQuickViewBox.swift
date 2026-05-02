//
//  EditorQuickViewBox.swift
//  Macintora
//
//  Bridge object that lets the SwiftUI menu command (in
//  `MainDocumentMenuCommands`) trigger Quick View on the focused editor
//  without holding a direct reference to the AppKit text view.
//
//  - `MainDocumentView` owns a single instance of this box and publishes it
//    via `.focusedSceneValue(\.editorQuickViewBox, ...)`.
//  - The editor's coordinator (`MacintoraEditorRepresentable.Coordinator`)
//    writes a `[weak self, weak textView]` closure into `trigger` once the
//    Quick View controller is installed, and clears it when the editor is
//    dismantled.
//  - The menu command reads the focused box from anywhere in the responder
//    hierarchy and invokes `trigger?()`.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class EditorQuickViewBox {
    /// Set by the editor's coordinator after Quick View has been wired.
    /// Reading nil means no editor is currently capable of Quick View
    /// (read-only viewer, completion config not yet installed, etc.).
    var trigger: (() -> Void)?
}

// MARK: - FocusedValueKey

struct EditorQuickViewBoxKey: FocusedValueKey {
    typealias Value = EditorQuickViewBox
}

extension FocusedValues {
    var editorQuickViewBox: EditorQuickViewBoxKey.Value? {
        get { self[EditorQuickViewBoxKey.self] }
        set { self[EditorQuickViewBoxKey.self] = newValue }
    }
}

// MARK: - View modifier

extension View {
    /// Conditionally applies the `.keyboardShortcut(...)` modifier only when
    /// the hotkey enum carries a key equivalent. When the user has chosen
    /// "Disabled", no shortcut is bound.
    @ViewBuilder
    func quickViewShortcut(_ hotkey: QuickViewHotkey) -> some View {
        if let key = hotkey.keyEquivalent {
            self.keyboardShortcut(key, modifiers: hotkey.modifiers)
        } else {
            self
        }
    }
}
