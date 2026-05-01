//
//  ConnectionExecutor.swift
//  Macintora
//
//  Protocol over the OracleNIO call path. Phase 2 ships only the protocol
//  shape and a no-op default; Phase 4 lands the real impl that drives a
//  live `OracleConnection`. Tests use the fake in
//  `MacintoraTests/Results/FakeConnectionExecutor.swift`.
//

import Foundation

/// What the runner hands an executor for one unit.
struct PreparedUnit: Sendable {
    let unit: CommandUnit
    /// Substituted text ready to send to Oracle (terminator stripped).
    let resolvedText: String
    /// Bind values keyed by uppercased name (no leading `:`).
    let binds: [String: BindValue]
}

protocol ConnectionExecutor: Sendable {
    /// Execute one unit. Implementations run DB I/O off the main actor and
    /// translate OracleNIO outcomes into a `UnitResult`. Throws on
    /// cancellation or unrecoverable transport failures.
    ///
    /// `@concurrent` opts out of Swift 6.2 approachable concurrency's "run on
    /// caller's actor" default — DB I/O must run on the global executor so it
    /// doesn't pin the main actor.
    @concurrent
    func execute(_ prepared: PreparedUnit) async throws -> UnitResult

    /// Best-effort cancellation of the current in-flight unit. Implementations
    /// should be safe to call concurrently with `execute`.
    @concurrent
    func cancel() async
}
