//
//  EditorOpenInBrowserBox.swift
//  Macintora
//
//  Bridge object that lets the SwiftUI menu command (⌥⌘B) trigger
//  "Open in DB Browser" on the focused editor without holding a direct
//  reference to the AppKit text view.
//
//  Mirrors the `EditorQuickViewBox` pattern — intentionally **not**
//  `@Observable` to avoid the menu-invalidation → constraint-loop crash
//  described in `EditorQuickViewBox.swift`.
//
//  - `MainDocumentView` owns a single instance and publishes it via
//    `.focusedSceneValue(\.editorOpenInBrowserBox, ...)`.
//  - The editor's coordinator writes the `trigger` closure after wiring
//    `QuickViewController.openInBrowserHandler`.
//  - The menu command reads the focused box and invokes `trigger?()`.
//

import Foundation
import SwiftUI

@MainActor
final class EditorOpenInBrowserBox {
    var trigger: (() -> Void)?
}

// MARK: - FocusedValueKey

struct EditorOpenInBrowserBoxKey: FocusedValueKey {
    typealias Value = EditorOpenInBrowserBox
}

extension FocusedValues {
    var editorOpenInBrowserBox: EditorOpenInBrowserBoxKey.Value? {
        get { self[EditorOpenInBrowserBoxKey.self] }
        set { self[EditorOpenInBrowserBoxKey.self] = newValue }
    }
}
