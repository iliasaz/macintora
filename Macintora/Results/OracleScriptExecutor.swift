//
//  OracleScriptExecutor.swift
//  Macintora
//
//  `ConnectionExecutor` implementation that drives a live `OracleConnection`.
//  Mirrors the inline execution body in `ResultViewModel.populateData`, but
//  shapes its output as a `UnitResult` (with bounded `RowsPreview` for the
//  Script Output pane) rather than mutating the legacy view model.
//
//  All DB I/O runs off the main actor — methods are `nonisolated` and the
//  oracle-nio calls are `@concurrent` already.
//

import Foundation
import OracleNIO
import Logging

struct OracleScriptExecutor: ConnectionExecutor, Sendable {
    let conn: OracleConnection
    let logger: Logging.Logger
    /// Toggle for `DBMS_OUTPUT.ENABLE` + drain. SQL*Plus `SET SERVEROUTPUT`
    /// flips this in Phase 6; for now the runner just passes `true`.
    let dbmsOutputEnabled: Bool
    /// Cap on rows captured for the inline `RowsPreview`. Beyond this we set
    /// `truncated = true` and let the user promote to the full grid.
    let previewCap: Int

    init(
        conn: OracleConnection,
        logger: Logging.Logger,
        dbmsOutputEnabled: Bool = true,
        previewCap: Int = RowsPreview.defaultRowCap
    ) {
        self.conn = conn
        self.logger = logger
        self.dbmsOutputEnabled = dbmsOutputEnabled
        self.previewCap = previewCap
    }

    @concurrent
    func execute(_ prepared: PreparedUnit) async throws -> UnitResult {
        let start = ContinuousClock.now

        switch prepared.unit.kind {
        case .sqlplus:
            // v1: directives that need DB calls (SHOW ERRORS) are handled in
            // Phase 6; remaining ones are pure session-state mutations and
            // get a free pass here.
            return UnitResult(
                outcome: .directiveAcknowledged,
                elapsed: ContinuousClock.now - start
            )

        case .sql, .plsqlBlock:
            return try await runStatement(prepared, start: start)
        }
    }

    @concurrent
    func cancel() async {
        // No-op: cancellation propagates from the runner's parent Task into
        // the in-flight `try await` on the row iterator.
    }

    // MARK: - Statement execution

    @concurrent
    private func runStatement(_ prepared: PreparedUnit, start: ContinuousClock.Instant) async throws -> UnitResult {
        if dbmsOutputEnabled {
            try? await DBMSOutput.enable(on: conn, logger: logger)
        }

        do {
            let statement = BindValue.makeStatement(sql: prepared.resolvedText, binds: prepared.binds)
            let stream = try await conn.execute(statement, logger: logger)
            let columns = DisplayRowBuilder.columnLabels(for: stream.columns)

            var iterator = stream.makeAsyncIterator()
            var collected: [[String]] = []
            var idx = 0
            var exhausted = false

            while idx < previewCap {
                if Task.isCancelled { throw CancellationError() }
                guard let row = try await iterator.next() else {
                    exhausted = true
                    break
                }
                let display = DisplayRowBuilder.make(from: row, id: idx, columnLabels: columns)
                collected.append(display.values)
                idx += 1
            }

            // If we hit the cap, peek for a single more row to mark `truncated`.
            // We deliberately don't drain past that — the rest sits in the
            // server cursor until the user promotes the preview.
            var truncated = false
            if !exhausted {
                if (try? await iterator.next()) != nil {
                    truncated = true
                }
            }

            // DBMS_OUTPUT can only be drained when the cursor is exhausted; if
            // the cursor is still mid-scan, oracle-nio serializes and would
            // deadlock against the open cursor (see `ResultViewModel`).
            let dbmsLines: [String]
            if exhausted, dbmsOutputEnabled {
                let raw = (try? await DBMSOutput.drain(on: conn, logger: logger)) ?? ""
                dbmsLines = raw.isEmpty ? [] : raw.components(separatedBy: "\n")
            } else {
                dbmsLines = []
            }

            let rowCount = columns.isEmpty ? nil : collected.count
            let preview = previewFrom(columns: columns, rows: collected, truncated: truncated)
            return UnitResult(
                outcome: .statementSucceeded(rowCount: rowCount, dbmsOutput: dbmsLines, preview: preview),
                elapsed: ContinuousClock.now - start
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let appErr = AppDBError.from(error)
            let oraCode = parseOracleErrorCode(appErr.code)
            return UnitResult(
                outcome: .statementFailed(message: appErr.description, oracleErrorCode: oraCode),
                elapsed: ContinuousClock.now - start
            )
        }
    }

    private func previewFrom(columns: [String], rows: [[String]], truncated: Bool) -> RowsPreview? {
        guard !columns.isEmpty else { return nil }
        return RowsPreview(columns: columns, rows: rows, truncated: truncated)
    }
}

private func parseOracleErrorCode(_ code: String?) -> Int? {
    guard let code, code.hasPrefix("ORA-") else { return nil }
    let digits = code.dropFirst(4).trimmingCharacters(in: .whitespaces)
    return Int(digits)
}
