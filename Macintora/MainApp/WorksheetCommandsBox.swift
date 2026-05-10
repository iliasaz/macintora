//
//  WorksheetCommandsBox.swift
//  Macintora
//
//  Bridge object that lets SwiftUI menu commands (Database menu) trigger
//  worksheet actions on the focused document — Run, Stop, Run Script,
//  Run From Cursor / Selection, Explain Plan, Compile, Format — without
//  the menu commands holding a direct reference to the document VM.
//
//  Mirrors the `EditorQuickViewBox` pattern: intentionally **not**
//  `@Observable` so trigger reassignment doesn't cascade menu redraws into
//  the constraint-loop crash described in `EditorQuickViewBox.swift`.
//
//  The companion `worksheetIsConnected` / `worksheetIsExecuting` focused
//  scene values carry the state the menu needs for `.disabled(...)`. They
//  are plain values (not boxes) so SwiftUI republishes them on each
//  document body redraw and the menu item enable state stays in sync.
//

import Foundation
import SwiftUI

@MainActor
final class WorksheetCommandsBox {
    var runCurrent: (() -> Void)?
    var stop: (() -> Void)?
    var runScript: (() -> Void)?
    var runFromCursorOrSelection: (() -> Void)?
    var explainPlan: (() -> Void)?
    var compile: (() -> Void)?
    var format: (() -> Void)?
}

// MARK: - FocusedValueKeys

struct WorksheetCommandsBoxKey: FocusedValueKey {
    typealias Value = WorksheetCommandsBox
}

struct WorksheetIsConnectedKey: FocusedValueKey {
    typealias Value = ConnectionStatus
}

struct WorksheetIsExecutingKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var worksheetCommandsBox: WorksheetCommandsBoxKey.Value? {
        get { self[WorksheetCommandsBoxKey.self] }
        set { self[WorksheetCommandsBoxKey.self] = newValue }
    }

    var worksheetIsConnected: WorksheetIsConnectedKey.Value? {
        get { self[WorksheetIsConnectedKey.self] }
        set { self[WorksheetIsConnectedKey.self] = newValue }
    }

    var worksheetIsExecuting: WorksheetIsExecutingKey.Value? {
        get { self[WorksheetIsExecutingKey.self] }
        set { self[WorksheetIsExecutingKey.self] = newValue }
    }
}
