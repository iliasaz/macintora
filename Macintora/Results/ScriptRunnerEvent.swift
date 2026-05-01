//
//  ScriptRunnerEvent.swift
//  Macintora
//
//  Events emitted by `ScriptRunner` over its `AsyncStream`. UI consumers
//  subscribe on the main actor; the runner stays on its own actor.
//

import Foundation

/// One outcome of executing a single command unit.
struct UnitResult: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// SQL*Plus directive successfully applied (no DB call needed).
        case directiveAcknowledged
        /// SQL/PL-SQL statement ran successfully. `preview` carries a bounded
        /// snapshot of returned rows (nil for non-SELECT).
        case statementSucceeded(rowCount: Int?, dbmsOutput: [String], preview: RowsPreview?)
        /// Statement failed. `oracleErrorCode` is the ORA-NNNNN integer or nil
        /// for non-Oracle errors (cancellation, network, etc.).
        case statementFailed(message: String, oracleErrorCode: Int?)
    }

    let outcome: Outcome
    /// Wall-clock duration of the unit (excluding bind / substitution prompts).
    let elapsed: Duration
}

/// A request from the runner to gather data from the user. The runner pauses
/// until `resume` is invoked.
struct BindRequest: Sendable {
    let unitIndex: Int
    let names: Set<String>
    /// Resolves with bind values, or nil to abort the script.
    let resume: @Sendable ([String: BindValue]?) -> Void
}

struct SubstitutionRequest: Sendable {
    let names: Set<String>
    let stickyNames: Set<String>
    /// Resolves with name→value (uppercased keys), or nil to abort.
    let resume: @Sendable ([String: String]?) -> Void
}

enum ScriptRunnerEvent: Sendable {
    case unitStarted(index: Int, total: Int, unit: CommandUnit)
    case unitFinished(index: Int, result: UnitResult)
    case needsBinds(BindRequest)
    case needsSubstitutions(SubstitutionRequest)
    case cancelled
    case scriptFinished
}
