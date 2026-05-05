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

/// Plain reference-type holder — intentionally **not** `@Observable`.
///
/// The trigger closure is rebound from `updateNSView`'s install path each
/// time the editor's coordinator wires Quick View. If this class were
/// observable, every rebind would invalidate `MainDocumentMenuCommands`
/// (which reads `box.trigger` for `.disabled(...)`), and that invalidation
/// cascading through the @FocusedSceneValue subscription was enough to
/// drive `_NSSplitViewItemViewWrapper.updateConstraints` into the
/// "more Update Constraints passes than views" loop AppKit aborts on —
/// the same crash signature as `SidebarToggleCrashRegressionTests`.
///
/// The menu command instead disables on box identity (nil vs non-nil),
/// which is settled at focus-publish time and doesn't re-fire on closure
/// reassignment.
@MainActor
final class EditorQuickViewBox {
    /// Set by the editor's coordinator after Quick View has been wired.
    /// nil during the brief window before `installQuickViewController`
    /// runs — pressing ⌘I in that window is a silent no-op (the closure
    /// invocation simply does nothing), which is preferable to the menu
    /// re-render storm that observability would cause.
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

