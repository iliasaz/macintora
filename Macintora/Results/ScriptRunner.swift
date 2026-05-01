//
//  ScriptRunner.swift
//  Macintora
//
//  Drives sequential execution of a script's CommandUnits against a
//  `ConnectionExecutor`. Single owner of cancellation; emits events over an
//  `AsyncStream` that UI consumers iterate on the main actor.
//
//  Directive application + `&` substitution happens *inline* during the run
//  loop so mid-script `DEFINE` and `WHENEVER SQLERROR` mutations are honored
//  by subsequent units. Bind-variable values are gathered per-unit via the
//  `needsBinds` event.
//
//  Note: `SET SERVEROUTPUT` mid-run mutation is intentionally not honored —
//  the executor captures `dbmsOutputEnabled` at construction time. The
//  caller pre-scans the script for the final SERVEROUTPUT setting and
//  passes it to the executor's init.
//

import Foundation

/// Static knobs that don't depend on the script's directive state.
struct ScriptRunnerOptions: Sendable {
    /// User-level "always halt on error" override. When `true`, the runner
    /// halts on the first failure regardless of the script's
    /// `WHENEVER SQLERROR` setting. The default is `false` so the env
    /// drives behaviour.
    var alwaysStopOnError: Bool = false
}

actor ScriptRunner {
    private let units: [CommandUnit]
    private let executor: any ConnectionExecutor
    private let env: SqlPlusEnvironment
    private let options: ScriptRunnerOptions
    private var isCancelled = false
    /// The most recent CREATE [OR REPLACE] target the runner has seen.
    /// Used by SHOW ERRORS to decide which object to query USER_ERRORS for.
    private var lastStoredProc: StoredProc?

    init(
        units: [CommandUnit],
        executor: any ConnectionExecutor,
        env: SqlPlusEnvironment,
        options: ScriptRunnerOptions = .init()
    ) {
        self.units = units
        self.executor = executor
        self.env = env
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
        defer { continuation.finish() }

        for (idx, unit) in units.enumerated() {
            if isCancelled || Task.isCancelled {
                continuation.yield(.cancelled)
                return
            }
            continuation.yield(.unitStarted(index: idx, total: units.count, unit: unit))

            let result: UnitResult
            switch unit.kind {
            case .sqlplus(let directive):
                result = await applyDirective(directive)

            case .sql, .plsqlBlock:
                let outcome = await runSqlOrPlsql(unit: unit, index: idx, continuation: continuation)
                switch outcome {
                case .result(let r):
                    result = r
                case .cancelled:
                    continuation.yield(.cancelled)
                    return
                }
                // Track the most recent CREATE target so a subsequent SHOW
                // ERRORS knows what to query USER_ERRORS for.
                if case .plsqlBlock = unit.kind {
                    let runnable = RunnableSQL(sql: unit.text)
                    if let proc = runnable.storedProc { lastStoredProc = proc }
                }
            }

            continuation.yield(.unitFinished(index: idx, result: result))

            if case .statementFailed = result.outcome {
                if options.alwaysStopOnError || env.shouldHaltOnError {
                    continuation.yield(.scriptFinished)
                    return
                }
            }
        }

        continuation.yield(.scriptFinished)
    }

    // MARK: - Per-unit handlers

    private func applyDirective(_ directive: SqlPlusDirective) async -> UnitResult {
        let start = ContinuousClock.now
        let outcome = SqlPlusInterpreter.apply(directive, env: env)

        switch outcome {
        case .showErrors:
            return await fetchAndPackageCompileErrors(start: start)
        case .acknowledged, .skip, .prompt, .noted, .unresolvedInclude:
            return UnitResult(
                outcome: .directiveAcknowledged,
                elapsed: ContinuousClock.now - start
            )
        }
    }

    private func fetchAndPackageCompileErrors(start: ContinuousClock.Instant) async -> UnitResult {
        guard let proc = lastStoredProc else {
            return UnitResult(
                outcome: .directiveCompileErrors(target: nil, errors: []),
                elapsed: ContinuousClock.now - start
            )
        }
        let target = CompileErrorTarget(owner: proc.owner, name: proc.name, type: proc.type)
        do {
            let rows = try await executor.fetchCompileErrors(for: target)
            return UnitResult(
                outcome: .directiveCompileErrors(target: target, errors: rows),
                elapsed: ContinuousClock.now - start
            )
        } catch {
            return UnitResult(
                outcome: .statementFailed(message: "SHOW ERRORS failed: \(error.localizedDescription)", oracleErrorCode: nil),
                elapsed: ContinuousClock.now - start
            )
        }
    }

    private enum UnitOutcome {
        case result(UnitResult)
        case cancelled
    }

    private func runSqlOrPlsql(
        unit: CommandUnit,
        index: Int,
        continuation: AsyncStream<ScriptRunnerEvent>.Continuation
    ) async -> UnitOutcome {
        let resolvedText = env.defineEnabled
            ? SubstitutionResolver.resolve(unit.text, defines: env.defines).text
            : unit.text

        // Bind prompt — pause until bridge resumes with values (or nil).
        let bindNames = RunnableSQL.scanBindVars(resolvedText)
        var binds: [String: BindValue] = [:]
        if !bindNames.isEmpty {
            guard let collected = await collectBinds(unitIndex: index, names: bindNames, continuation: continuation) else {
                return .cancelled
            }
            binds = collected
        }

        if isCancelled || Task.isCancelled {
            return .cancelled
        }

        let prepared = PreparedUnit(unit: unit, resolvedText: resolvedText, binds: binds)
        let start = ContinuousClock.now
        do {
            let executed = try await executor.execute(prepared)
            return .result(executed)
        } catch is CancellationError {
            return .cancelled
        } catch {
            let elapsed = ContinuousClock.now - start
            let oraCode = (error as? any OracleErrorCarrier)?.oracleErrorCode
            return .result(UnitResult(
                outcome: .statementFailed(message: error.localizedDescription, oracleErrorCode: oraCode),
                elapsed: elapsed
            ))
        }
    }

    private func collectBinds(
        unitIndex: Int,
        names: Set<String>,
        continuation: AsyncStream<ScriptRunnerEvent>.Continuation
    ) async -> [String: BindValue]? {
        await withCheckedContinuation { (cc: CheckedContinuation<[String: BindValue]?, Never>) in
            let request = BindRequest(
                unitIndex: unitIndex,
                names: names,
                resume: { values in cc.resume(returning: values) }
            )
            continuation.yield(.needsBinds(request))
        }
    }
}

extension SqlPlusEnvironment {
    /// Convenience for the runner: should the script halt on the most recent
    /// failure given the current `WHENEVER` action?
    var shouldHaltOnError: Bool {
        if case .exit = whenever { return true }
        return false
    }
}

/// Thin marker so executors can hand back ORA-NNNNN codes without forcing
/// every caller to know about OracleNIO error types.
protocol OracleErrorCarrier: Error {
    var oracleErrorCode: Int? { get }
}
