//
//  ScriptOutput.swift
//  Macintora
//
//  Observable model + value types backing the Script Output pane. One
//  `ScriptOutputEntry` per executed unit (or per cancellation / note). The
//  model is passive — the bridge in `ResultsController` (Phase 4) consumes
//  `ScriptRunnerEvent`s and appends entries.
//

import Foundation

@Observable @MainActor
final class ScriptOutputModel {
    var entries: [ScriptOutputEntry] = []
    var isRunning: Bool = false
    var currentUnitIndex: Int? = nil
    var totalUnits: Int = 0

    func clear() {
        entries.removeAll()
        currentUnitIndex = nil
        totalUnits = 0
    }

    func beginRun(totalUnits: Int) {
        clear()
        isRunning = true
        self.totalUnits = totalUnits
    }

    func finishRun() {
        isRunning = false
        currentUnitIndex = nil
    }

    func setCurrentUnit(_ index: Int) {
        currentUnitIndex = index
    }

    func append(_ entry: ScriptOutputEntry) {
        entries.append(entry)
    }

    func note(_ kind: NoteEntry.Kind, text: String) {
        entries.append(.note(.init(id: UUID(), kind: kind, text: text)))
    }
}

enum ScriptOutputEntry: Identifiable, Hashable, Sendable {
    case directive(DirectiveEntry)
    case prompt(PromptEntry)
    case succeeded(SucceededEntry)
    case failed(FailedEntry)
    case note(NoteEntry)

    var id: UUID {
        switch self {
        case .directive(let e): return e.id
        case .prompt(let e): return e.id
        case .succeeded(let e): return e.id
        case .failed(let e): return e.id
        case .note(let e): return e.id
        }
    }
}

struct DirectiveEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let elapsed: Duration
}

struct PromptEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let message: String
}

struct SucceededEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let unitIndex: Int
    /// The user-visible unit text (resolved, terminator stripped).
    let text: String
    let kind: UnitKind
    let elapsed: Duration
    /// `nil` for non-DML statements (DDL / SELECT before fetch / PL/SQL).
    let rowCount: Int?
    let dbmsOutput: [String]
    /// In-memory preview of returned rows for SELECTs.
    let preview: RowsPreview?
}

struct FailedEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let unitIndex: Int
    let text: String
    let kind: UnitKind
    let elapsed: Duration
    let message: String
    let oracleErrorCode: Int?
    /// Range in the *original* (un-substituted) script for click-to-source.
    /// `nil` when the entry comes from a synthetic source (e.g. typed input).
    let originalUTF16Range: Range<Int>?
}

struct NoteEntry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case cancelled, info, warning }
    let id: UUID
    let kind: Kind
    let text: String
}

/// Lightweight echo of `CommandUnit.Kind` that drops the directive payload —
/// the output entries don't need it after the directive has been interpreted.
enum UnitKind: Hashable, Sendable {
    case sql
    case plsqlBlock
    case sqlplus
}

extension UnitKind {
    init(_ kind: CommandUnit.Kind) {
        switch kind {
        case .sql: self = .sql
        case .plsqlBlock: self = .plsqlBlock
        case .sqlplus: self = .sqlplus
        }
    }
}

/// Bounded snapshot of returned rows shown inline in the Script Output pane.
/// Promotion to the full result grid copies these into a regular
/// `ResultViewModel`.
struct RowsPreview: Hashable, Sendable {
    let columns: [String]
    let rows: [[String]]
    let truncated: Bool

    static let defaultRowCap = 200
}
