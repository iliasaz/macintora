//
//  EditorToggleCommentBox.swift
//  Macintora
//
//  Bridge object that lets the SwiftUI menu command (⌘/) trigger
//  Toggle Line Comment on the focused editor without holding a direct
//  reference to the AppKit text view.
//
//  Mirrors the `EditorQuickViewBox` pattern — intentionally **not**
//  `@Observable` to avoid the menu-invalidation → constraint-loop crash
//  described in `EditorQuickViewBox.swift`.
//

import Foundation
import SwiftUI

@MainActor
final class EditorToggleCommentBox {
    var trigger: (() -> Void)?
}

// MARK: - FocusedValueKey

struct EditorToggleCommentBoxKey: FocusedValueKey {
    typealias Value = EditorToggleCommentBox
}

extension FocusedValues {
    var editorToggleCommentBox: EditorToggleCommentBoxKey.Value? {
        get { self[EditorToggleCommentBoxKey.self] }
        set { self[EditorToggleCommentBoxKey.self] = newValue }
    }
}
