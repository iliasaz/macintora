//
//  SessionBrowserBox.swift
//  Macintora
//
//  Bridge object that lets the SwiftUI menu command (⌃⇧⌘S) open the
//  Session Browser without the menu command needing to know the focused
//  document's connection. Mirrors `EditorOpenInBrowserBox`: the document
//  view installs a trigger closure capturing `[weak document]` plus the
//  scene's `OpenWindowAction`, and the menu command just calls
//  `box.trigger?()` — no `@FocusedValue(\.mainConnection)` read at the
//  call site.
//

import Foundation
import SwiftUI

@MainActor
final class SessionBrowserBox {
    var trigger: (() -> Void)?
}

// MARK: - FocusedValueKey

struct SessionBrowserBoxKey: FocusedValueKey {
    typealias Value = SessionBrowserBox
}

extension FocusedValues {
    var sessionBrowserBox: SessionBrowserBoxKey.Value? {
        get { self[SessionBrowserBoxKey.self] }
        set { self[SessionBrowserBoxKey.self] = newValue }
    }
}
