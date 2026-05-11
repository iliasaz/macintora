//
//  DBBrowserCommandsBox.swift
//  Macintora
//
//  Bridge object that lets SwiftUI menu commands trigger DB Browser actions
//  on the focused window — Refresh, Clear, focus search, switch tabs — so
//  every toolbar item has a menu-bar peer with a standard key equivalent
//  (HIG: "Make every toolbar item available as a command in the menu bar.")
//
//  Follows the `WorksheetCommandsBox` pattern: intentionally **not**
//  `@Observable` so trigger reassignment doesn't cascade menu redraws into
//  a constraint-loop crash.
//

import Foundation
import SwiftUI

@MainActor
final class DBBrowserCommandsBox {
    var incrementalRefresh: (() -> Void)?
    var fullRefresh: (() -> Void)?
    var fullRefreshAndCompact: (() -> Void)?
    var compactOnly: (() -> Void)?
    var clear: (() -> Void)?
    var showCounts: (() -> Void)?
    var focusSearch: (() -> Void)?
    var clearSearch: (() -> Void)?
    var selectMainTab: (() -> Void)?
    var selectDetailsTab: (() -> Void)?
    var editSource: (() -> Void)?
    var refreshObject: (() -> Void)?
}

// MARK: - FocusedValueKeys

struct DBBrowserCommandsBoxKey: FocusedValueKey {
    typealias Value = DBBrowserCommandsBox
}

struct DBBrowserIsReloadingKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var dbBrowserCommandsBox: DBBrowserCommandsBoxKey.Value? {
        get { self[DBBrowserCommandsBoxKey.self] }
        set { self[DBBrowserCommandsBoxKey.self] = newValue }
    }

    var dbBrowserIsReloading: DBBrowserIsReloadingKey.Value? {
        get { self[DBBrowserIsReloadingKey.self] }
        set { self[DBBrowserIsReloadingKey.self] = newValue }
    }
}
