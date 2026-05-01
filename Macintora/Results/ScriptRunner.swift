//
//  ScriptRunner.swift
//  Macintora
//
//  Drives sequential execution of a script's CommandUnits against a
//  `ConnectionExecutor`. Single owner of cancellation; emits events over an
//  `AsyncStream` that UI consumers iterate on the main actor.
//
//  Phase 2 scope: protocol + types + serial execution loop with a fake
//  executor in tests. Wiring against a real OracleConnection is Phase 4;
//  bind / substitution prompts and SQL*Plus side effects are Phase 5/6.
//

import Foundation

/// Configuration knobs the script-runner needs at construction time.
struct ScriptRunnerOptions: Sendable {
    /// Stop the script on the first failed unit. Phase 6 will replace this
    /// with the SQL*Plus `WHENEVER SQLERROR` setting; for now it's a simple
    /// boolean.
    var stopOnError: Bool = true
}

actor ScriptRunner {
    private let units: [CommandUnit]
    private let executor: any ConnectionExecutor
    private let options: ScriptRunnerOptions
    private var continuation: AsyncStream<ScriptRunnerEvent>.Continuation?
    private var isCancelled = false

    init(
        units: [CommandUnit],
        executor: any ConnectionExecutor,
        options: ScriptRunnerOptions = .init()
    ) {
        self.units = units
        self.executor = executor
        self.options = options
    }

    /// Begin execution. Returns the event stream the caller should iterate.
    /// The stream finishes after `scriptFinished` (or `cancelled`) is emitted.
    nonisolated func start() -> AsyncStream<ScriptRunnerEvent> {
        AsyncStream { continuation in
            // Detached so the run loop dispatches off the caller's actor.
            // (Approachable concurrency would otherwise pin the loop to
            // whichever actor invoked `start()`.)
            let task = Task.detached { @concurrent [weak self] in
                await self?.run(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Cancel a script that's mid-flight. Idempotent.
    func cancel() async {
        guard !isCancelled else { return }
        isCancelled = true
        await executor.cancel()
    }

    private func run(continuation: AsyncStream<ScriptRunnerEvent>.Continuation) async {
        self.continuation = continuation
        defer {
            continuation.finish()
        }

        for (idx, unit) in units.enumerated() {
            if isCancelled || Task.isCancelled {
                continuation.yield(.cancelled)
                return
            }

            continuation.yield(.unitStarted(index: idx, total: units.count, unit: unit))

            // Phase 2 path: no bind/substitution prompts; pass unit text through.
            let prepared = PreparedUnit(
                unit: unit,
                resolvedText: unit.text,
                binds: [:]
            )

            let start = ContinuousClock.now
            let result: UnitResult
            do {
                let executed = try await executor.execute(prepared)
                result = executed
            } catch is CancellationError {
                continuation.yield(.cancelled)
                return
            } catch {
                let elapsed = ContinuousClock.now - start
                let oraCode = (error as? any OracleErrorCarrier)?.oracleErrorCode
                result = UnitResult(
                    outcome: .statementFailed(message: error.localizedDescription, oracleErrorCode: oraCode),
                    elapsed: elapsed
                )
            }

            continuation.yield(.unitFinished(index: idx, result: result))

            if case .statementFailed = result.outcome, options.stopOnError {
                continuation.yield(.scriptFinished)
                return
            }
        }

        continuation.yield(.scriptFinished)
    }
}

/// Thin marker so executors can hand back ORA-NNNNN codes without forcing
/// every caller to know about OracleNIO error types.
protocol OracleErrorCarrier: Error {
    var oracleErrorCode: Int? { get }
}
