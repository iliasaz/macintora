import Foundation
import OracleNIO
import Logging

@MainActor
@Observable
final class ResultsController {
    weak var document: MainDocumentVM?
    var results: [String: ResultViewModel]
    var isExecuting = false

    // MARK: - Script-mode plumbing
    //
    // Coexists with the legacy single-statement path; nothing touches these
    // fields unless `runScript` is invoked. The UI swap (ResultViewWrapper)
    // lands in Phase 5 alongside menu wiring.
    /// Output stream for the in-progress / most recent script.
    let scriptOutput = ScriptOutputModel()
    /// Whether the user is currently looking at script output (vs the
    /// single-statement grid + log).
    var isScriptMode: Bool = false
    /// Set when the runner needs values for unresolved `&` / `&&` variables;
    /// observed by `MainDocumentView` to present `SubstitutionInputView`.
    var pendingSubstitution: PendingSubstitutionRequest?
    /// Session-sticky `&&` values, persisted for this document's lifetime.
    private var sessionDefines: [String: String] = [:]
    private var pendingResolve: (([String: String]?) -> Void)?

    private var scriptRunner: ScriptRunner?
    private var scriptRunnerTask: Task<Void, Never>?
    private var scriptUnits: [CommandUnit] = []
    private var scriptSource: String = ""

    init(document: MainDocumentVM) {
        self.document = document
        self.results = [:]
        addResultVM()
    }

    func addResultVM() {
        self.results = ["current": ResultViewModel(parent: self)]
    }

    func runSQL(_ runnableSQL: RunnableSQL) {
        // Single-statement path returns to legacy grid + log.
        isScriptMode = false
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.promptForBindsAndExecute(for: runnableSQL, using: conn)
    }

    func explainPlan(for sql: String) {
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.explainPlan(for: sql, using: conn)
    }

    func compileSource(for runnableSQL: RunnableSQL) {
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.compileSource(for: runnableSQL, using: conn)
    }

    func cancelCurrent() {
        let resultVM = results["current"]!
        resultVM.cancel()
        cancelScript()
    }

    // MARK: - Script execution

    /// Run a script. `range` selects a slice of `source`; pass `nil` to run
    /// the whole document.
    func runScript(source: String, range: Range<String.Index>? = nil) {
        guard let conn = document?.conn else { return }

        let scriptText: String
        if let range {
            scriptText = String(source[range])
        } else {
            scriptText = source
        }

        let units = ScriptLexer.split(scriptText).units
        guard !units.isEmpty else {
            scriptOutput.note(.info, text: "No statements to run.")
            return
        }

        // Pre-scan for `&` / `&&` references; if any need values that aren't
        // already in `sessionDefines`, show the modal and resume on submit.
        let scan = SubstitutionResolver.scan(scriptText)
        let missing = scan.names.subtracting(sessionDefines.keys).sorted()

        if missing.isEmpty {
            startScriptExecution(scriptText: scriptText, units: units, conn: conn)
            return
        }

        let prefilled = sessionDefines.filter { scan.names.contains($0.key) }
        pendingSubstitution = PendingSubstitutionRequest(
            names: missing,
            stickyNames: scan.stickyNames,
            prefilled: prefilled
        )
        pendingResolve = { [weak self] result in
            guard let self else { return }
            self.pendingSubstitution = nil
            self.pendingResolve = nil
            guard let result else {
                self.scriptOutput.note(.cancelled, text: "Cancelled by user.")
                return
            }
            for name in scan.stickyNames {
                if let v = result[name] { self.sessionDefines[name] = v }
            }
            self.startScriptExecution(scriptText: scriptText, units: units, conn: conn)
        }
    }

    /// Resume a pending substitution prompt with `values` (or `nil` to cancel).
    func resolvePendingSubstitution(_ values: [String: String]?) {
        pendingResolve?(values)
    }

    private func startScriptExecution(scriptText: String, units: [CommandUnit], conn: OracleConnection) {
        let logger = oracleLoggerForScripts()

        // 1. Flatten @ / @@ includes against the document's directory.
        let flattened: [CommandUnit]
        do {
            flattened = try ScriptLoader.flatten(units, documentBaseURL: documentBaseURL())
        } catch {
            scriptOutput.note(.warning, text: "Include resolution failed: \(error)")
            isExecuting = false
            return
        }

        // 2. Build env, seed with session defines.
        let env = SqlPlusEnvironment()
        env.defines = sessionDefines

        // 3. Sequentially apply directives (mutating env) and substitute SQL
        //    units' text using env.defines at that point. Each unit's
        //    `originalRange` stays in the un-substituted top-level source
        //    (or, for included units, ranges into their own file — those
        //    won't navigate back to the editor but won't crash either).
        var preparedUnits: [CommandUnit] = []
        for unit in flattened {
            switch unit.kind {
            case .sqlplus(let directive):
                _ = SqlPlusInterpreter.apply(directive, env: env)
                preparedUnits.append(unit)
            case .sql, .plsqlBlock:
                let textToSend: String
                if env.defineEnabled {
                    textToSend = SubstitutionResolver.resolve(unit.text, defines: env.defines).text
                } else {
                    textToSend = unit.text
                }
                preparedUnits.append(CommandUnit(
                    kind: unit.kind,
                    originalRange: unit.originalRange,
                    text: textToSend
                ))
            }
        }

        // 4. Configure executor + runner from final env state.
        let stopOnError: Bool
        if case .exit = env.whenever { stopOnError = true } else { stopOnError = false }

        scriptUnits = preparedUnits
        scriptSource = scriptText
        isScriptMode = true
        isExecuting = true
        scriptOutput.beginRun(totalUnits: preparedUnits.count)

        let executor = OracleScriptExecutor(
            conn: conn,
            logger: logger,
            dbmsOutputEnabled: env.serverOutput
        )
        let runner = ScriptRunner(
            units: preparedUnits,
            executor: executor,
            options: .init(stopOnError: stopOnError)
        )
        scriptRunner = runner

        let stream = runner.start()
        scriptRunnerTask = Task { @MainActor in
            for await event in stream {
                self.handleScriptEvent(event)
            }
            self.isExecuting = false
        }
    }

    private func documentBaseURL() -> URL? {
        // The document file URL isn't directly exposed on `MainDocumentVM`
        // today; `@/@@` resolution falls back to `nil` until a future phase
        // surfaces it. Absolute paths still work via the loader's fallback.
        nil
    }

    /// Cancel an in-flight script. Idempotent.
    func cancelScript() {
        guard let runner = scriptRunner else { return }
        Task { @MainActor in
            await runner.cancel()
        }
    }

    private func handleScriptEvent(_ event: ScriptRunnerEvent) {
        switch event {
        case .unitStarted(let index, _, _):
            scriptOutput.setCurrentUnit(index)

        case .unitFinished(let index, let result):
            let unit = scriptUnits.indices.contains(index) ? scriptUnits[index] : nil
            scriptOutput.append(makeEntry(unitIndex: index, unit: unit, result: result))

        case .needsBinds, .needsSubstitutions:
            // Phase 5 wires consolidated prompts; for now the runner never
            // emits these (stubbed out).
            break

        case .cancelled:
            scriptOutput.note(.cancelled, text: "Cancelled by user.")
            scriptOutput.finishRun()
            isExecuting = false
            scriptRunner = nil

        case .scriptFinished:
            scriptOutput.finishRun()
            isExecuting = false
            scriptRunner = nil
        }
    }

    private func makeEntry(unitIndex: Int, unit: CommandUnit?, result: UnitResult) -> ScriptOutputEntry {
        let id = UUID()
        let text = unit?.text ?? ""
        let kind: UnitKind = unit.map { UnitKind($0.kind) } ?? .sql

        switch result.outcome {
        case .directiveAcknowledged:
            // Specialise display for prompt/remark so the output reads
            // naturally; everything else falls through to the generic
            // directive entry.
            if let unit, case .sqlplus(let directive) = unit.kind {
                switch directive {
                case .prompt(let message):
                    return .prompt(.init(id: id, message: message))
                case .remark:
                    return .note(.init(id: id, kind: .info, text: text))
                case .include(let path, let doubleAt):
                    let prefix = doubleAt ? "@@" : "@"
                    return .note(.init(id: id, kind: .warning, text: "Include not resolved: \(prefix)\(path)"))
                default:
                    break
                }
            }
            return .directive(.init(id: id, text: text, elapsed: result.elapsed))

        case .statementSucceeded(let rowCount, let dbmsOutput, let preview):
            return .succeeded(.init(
                id: id,
                unitIndex: unitIndex,
                text: text,
                kind: kind,
                elapsed: result.elapsed,
                rowCount: rowCount,
                dbmsOutput: dbmsOutput,
                preview: preview
            ))

        case .statementFailed(let message, let oracleErrorCode):
            let utf16Range: Range<Int>? = unit.map { unit in
                let lo = scriptSource.utf16.distance(
                    from: scriptSource.utf16.startIndex,
                    to: unit.originalRange.lowerBound.samePosition(in: scriptSource.utf16) ?? scriptSource.utf16.startIndex
                )
                let hi = scriptSource.utf16.distance(
                    from: scriptSource.utf16.startIndex,
                    to: unit.originalRange.upperBound.samePosition(in: scriptSource.utf16) ?? scriptSource.utf16.endIndex
                )
                return lo..<hi
            }
            return .failed(.init(
                id: id,
                unitIndex: unitIndex,
                text: text,
                kind: kind,
                elapsed: result.elapsed,
                message: message,
                oracleErrorCode: oracleErrorCode,
                originalUTF16Range: utf16Range
            ))
        }
    }

    private func oracleLoggerForScripts() -> Logging.Logger {
        var logger = Logging.Logger(label: "com.iliasazonov.macintora.script")
        logger.logLevel = .notice
        return logger
    }

    func displayError(_ error: any Error) {
        let resultVM = results["current"]!
        resultVM.displayError(AppDBError.from(error))
    }

    func clearError() {
        let resultVM = results["current"]!
        resultVM.clearError()
    }
}
