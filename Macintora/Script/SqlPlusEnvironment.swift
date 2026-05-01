//
//  SqlPlusEnvironment.swift
//  Macintora
//
//  Mutable session-state container threaded through script execution. Owns
//  the defines table, output toggles, and the WHENEVER SQLERROR action.
//  Mutated by `SqlPlusInterpreter` as the runner processes directives;
//  consumed by the runner when resolving `&` references in subsequent
//  units.
//

import Foundation

@MainActor
final class SqlPlusEnvironment {
    /// Currently-defined substitution variables (uppercased keys).
    var defines: [String: String] = [:]

    /// `SET SERVEROUTPUT ON|OFF` — drives the executor's DBMS_OUTPUT drain.
    var serverOutput: Bool = true

    /// `SET ECHO ON|OFF` — currently informational; Phase 7 may surface in
    /// the output entry presentation.
    var echo: Bool = false

    /// `SET FEEDBACK …` — informational; v1 doesn't suppress the rowcount
    /// summary based on this.
    var feedback: FeedbackMode = .on

    /// `SET DEFINE ON|OFF|<char>` — when off, `&` substitution is skipped.
    var defineEnabled: Bool = true

    /// `SET DEFINE <char>` — alternate substitution prefix. v1 only honors
    /// the on/off flag; switching the prefix is recognised but not yet
    /// applied during scanning.
    var definePrefix: Character = "&"

    /// `WHENEVER SQLERROR …` — read by the runner after each failed unit.
    var whenever: WheneverAction = .continue(.noAction)

    /// Names registered as `&&` somewhere in this run. Persisted into the
    /// document's session defines so the user isn't re-prompted.
    var stickyNames: Set<String> = []

    init() {}

    /// Snapshot for tests that need to assert state without holding a
    /// reference to the live env.
    func snapshot() -> Snapshot {
        Snapshot(
            defines: defines,
            serverOutput: serverOutput,
            echo: echo,
            feedback: feedback,
            defineEnabled: defineEnabled,
            definePrefix: definePrefix,
            whenever: whenever,
            stickyNames: stickyNames
        )
    }

    struct Snapshot: Equatable, Sendable {
        let defines: [String: String]
        let serverOutput: Bool
        let echo: Bool
        let feedback: FeedbackMode
        let defineEnabled: Bool
        let definePrefix: Character
        let whenever: WheneverAction
        let stickyNames: Set<String>
    }
}
