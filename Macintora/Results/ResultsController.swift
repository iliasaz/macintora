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
    /// Set when the runner needs `:bind` values for the current SQL/PLSQL
    /// unit; observed by `MainDocumentView` to present a `BindVarInputView`.
    var pendingBindRequest: PendingBindRequest?
    /// Session-sticky `&&` values, persisted for this document's lifetime.
    private var sessionDefines: [String: String] = [:]
    private var pendingResolve: (([String: String]?) -> Void)?

    /// User-level "halt on first error regardless of WHENEVER" override.
    /// Read from UserDefaults via `ScriptRunnerDefaults.alwaysStopOnError`
    /// at runScript time; defaults to false so the script's WHENEVER
    /// directive drives behaviour.
    var alwaysStopOnError: Bool {
        UserDefaults.standard.bool(forKey: ScriptRunnerDefaults.alwaysStopOnError)
    }

    /// Default initial value for the runner env's `serverOutput` flag.
    /// `SET SERVEROUTPUT` directives in the script can flip it pre-run via
    /// the executor's pre-scan.
    var scriptDbmsOutputDefault: Bool {
        if UserDefaults.standard.object(forKey: ScriptRunnerDefaults.dbmsOutputInline) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: ScriptRunnerDefaults.dbmsOutputInline)
    }

    /// Cap for inline `RowsPreview`. Falls back to `RowsPreview.defaultRowCap`
    /// when unset.
    var scriptMiniGridRowCap: Int {
        let v = UserDefaults.standard.integer(forKey: ScriptRunnerDefaults.miniGridRowCap)
        return v > 0 ? v : RowsPreview.defaultRowCap
    }

    private var scriptRunner: ScriptRunner?
    private var scriptRunnerTask: Task<Void, Never>?
    private var scriptUnits: [CommandUnit] = []
    private var scriptEnv: SqlPlusEnvironment?
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

        // 2. Build env, seed with session defines + user default for
        //    serverOutput.
        let env = SqlPlusEnvironment()
        env.defines = sessionDefines
        env.serverOutput = scriptDbmsOutputDefault

        // 3. Pre-scan SET SERVEROUTPUT to seed the executor's DBMS_OUTPUT
        //    capture. (Mid-run mutation isn't honored — the executor captures
        //    the value at construction. Tracked as a known limitation.)
        let initialServerOutput = preScanServerOutput(units: flattened, default: env.serverOutput)

        scriptUnits = flattened
        scriptEnv = env
        scriptSource = scriptText
        isScriptMode = true
        isExecuting = true
        scriptOutput.beginRun(totalUnits: flattened.count)

        let executor = OracleScriptExecutor(
            conn: conn,
            logger: logger,
            dbmsOutputEnabled: initialServerOutput,
            previewCap: scriptMiniGridRowCap
        )
        let runner = ScriptRunner(
            units: flattened,
            executor: executor,
            env: env,
            options: .init(alwaysStopOnError: alwaysStopOnError)
        )
        scriptRunner = runner

        let stream = runner.start()
        scriptRunnerTask = Task { @MainActor in
            for await event in stream {
                self.handleScriptEvent(event)
            }
            self.persistStickyDefines()
            self.isExecuting = false
        }
    }

    private func preScanServerOutput(units: [CommandUnit], default initial: Bool) -> Bool {
        var value = initial
        for unit in units {
            if case .sqlplus(.set(.serverOutput(let on))) = unit.kind {
                value = on
            }
        }
        return value
    }

    private func persistStickyDefines() {
        guard let env = scriptEnv else { return }
        for name in env.stickyNames {
            if let v = env.defines[name] { sessionDefines[name] = v }
        }
        scriptEnv = nil
    }

    private func documentBaseURL() -> URL? {
        // `@file.sql` resolves against the document's directory. For
        // untitled (unsaved) documents this is nil, in which case
        // `ScriptLoader` only succeeds for absolute paths.
        document?.fileURL?.deletingLastPathComponent()
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

        case .needsBinds(let request):
            pendingBindRequest = PendingBindRequest(
                id: UUID(),
                unitIndex: request.unitIndex,
                names: request.names,
                resume: request.resume
            )

        case .needsSubstitutions:
            // Up-front substitution prompt is handled in `runScript`; the
            // runner doesn't currently emit this event mid-run.
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

    /// Resume a pending bind prompt with `values` (or `nil` to cancel).
    func resolvePendingBinds(_ values: [String: BindValue]?) {
        guard let request = pendingBindRequest else { return }
        pendingBindRequest = nil
        request.resume(values)
    }

    /// Copy a `RowsPreview` into the legacy `ResultViewModel`'s grid and
    /// switch out of script mode so the user sees the full grid view.
    /// Used by the "Open in full grid" affordance on `MiniGridView`.
    func promote(preview: RowsPreview, sqlText: String) {
        let resultVM = results["current"]!
        let labels = ["#"] + preview.columns
        let rows = preview.rows.enumerated().map { (i, values) -> DisplayRow in
            var fields: [DisplayField] = []
            for (colIdx, columnName) in preview.columns.enumerated() {
                let valueString = colIdx < values.count ? values[colIdx] : ""
                fields.append(DisplayField(
                    name: columnName,
                    valueString: valueString,
                    sortKey: .text(valueString)
                ))
            }
            return DisplayRow(id: i, fields: fields)
        }
        resultVM.objectWillChange.send()
        resultVM.columnLabels = labels
        resultVM.rows = rows
        resultVM.currentSql = sqlText
        resultVM.isFailed = false
        isScriptMode = false
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

        case .directiveCompileErrors(let target, let errors):
            return .note(.init(id: id, kind: errors.isEmpty ? .info : .warning, text: formatCompileErrors(target: target, errors: errors)))

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

    private func formatCompileErrors(target: CompileErrorTarget?, errors: [CompileErrorRow]) -> String {
        guard let target else {
            return "SHOW ERRORS: no recently compiled object."
        }
        let header = "Errors for \(target.type) \(target.name)"
        if errors.isEmpty {
            return header + "\nNo errors."
        }
        let body = errors.map { row in
            "\(row.line)/\(row.position)\t\(row.attribute): \(row.text)"
        }.joined(separator: "\n")
        return header + "\n" + body
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
