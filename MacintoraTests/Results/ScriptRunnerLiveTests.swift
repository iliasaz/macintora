//
//  ScriptRunnerLiveTests.swift
//  MacintoraTests
//
//  Live integration: drives the runner against a real `OracleConnection`
//  using the saved `c4-local` connection. Skips when c4-local isn't
//  configured or its keychain password is missing — matching the pattern
//  in `FullRefreshReproTests`.
//

import XCTest
import OracleNIO
import Logging
@testable import Macintora

@MainActor
final class ScriptRunnerLiveTests: XCTestCase {

    func test_multi_statement_script_runs_against_c4Local() async throws {
        let conn = try await openLiveConnection()
        defer {
            Task { try? await conn.close() }
        }

        // Mix DDL/DML/SELECT/PL/SQL block + intentional ORA error.
        let script = """
        DROP TABLE macintora_script_test;
        CREATE TABLE macintora_script_test (id NUMBER, name VARCHAR2(20));
        INSERT INTO macintora_script_test VALUES (1, 'alice');
        INSERT INTO macintora_script_test VALUES (2, 'bob');
        SELECT id, name FROM macintora_script_test ORDER BY id;
        BEGIN
          DBMS_OUTPUT.PUT_LINE('hello from plsql');
        END;
        /
        SELECT * FROM macintora_no_such_table;
        DROP TABLE macintora_script_test;
        """

        let units = ScriptLexer.split(script).units
        XCTAssertGreaterThanOrEqual(units.count, 7, "expected the lexer to split into at least 7 units")

        let executor = OracleScriptExecutor(
            conn: conn,
            logger: Logging.Logger(label: "macintora.tests.script.live"),
            dbmsOutputEnabled: true
        )
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())

        var events: [ScriptRunnerEvent] = []
        for await event in runner.start() {
            events.append(event)
        }

        // Final event must be `scriptFinished` (we used stopOnError: false).
        guard case .scriptFinished = events.last else {
            return XCTFail("expected scriptFinished, got: \(String(describing: events.last))")
        }

        // Find the SELECT result and verify two rows came back.
        let selects = events.compactMap { event -> SucceededDescriptor? in
            guard case .unitFinished(_, let result) = event,
                  case .statementSucceeded(let rows, _, let preview) = result.outcome,
                  let rows, rows == 2,
                  let preview, preview.columns.contains(where: { $0.uppercased() == "ID" })
            else { return nil }
            return SucceededDescriptor(rowCount: rows, columns: preview.columns, rows: preview.rows)
        }
        XCTAssertEqual(selects.count, 1)
        if let descriptor = selects.first {
            XCTAssertEqual(descriptor.rowCount, 2)
            XCTAssertEqual(descriptor.rows.first?.last?.lowercased(), "alice")
        }

        // PL/SQL block produced DBMS_OUTPUT.
        let dbmsLines = events.compactMap { event -> [String]? in
            guard case .unitFinished(_, let result) = event,
                  case .statementSucceeded(_, let lines, _) = result.outcome,
                  !lines.isEmpty
            else { return nil }
            return lines
        }
        XCTAssertTrue(
            dbmsLines.flatMap { $0 }.contains(where: { $0.contains("hello from plsql") }),
            "expected DBMS_OUTPUT to capture the PL/SQL line; saw: \(dbmsLines)"
        )

        // The deliberate "no such table" hit produced a failure with ORA-942.
        let failures = events.compactMap { event -> Int? in
            guard case .unitFinished(_, let result) = event,
                  case .statementFailed(_, let code) = result.outcome
            else { return nil }
            return code
        }
        XCTAssertTrue(failures.contains(942), "expected ORA-00942 in failures; saw: \(failures)")
    }

    // MARK: - Helpers

    private struct SucceededDescriptor {
        let rowCount: Int
        let columns: [String]
        let rows: [[String]]
    }

    private func openLiveConnection() async throws -> OracleConnection {
        let store = ConnectionStore()
        guard let saved = store.connection(named: "c4-local") else {
            throw XCTSkip("c4-local not present in connections.json")
        }
        let appBundleID = "com.iliasazonov.macintora"
        let keychain = KeychainService(service: appBundleID)
        guard
            saved.savePasswordInKeychain,
            let pwd = try? keychain.password(for: saved.id, kind: .databasePassword),
            !pwd.isEmpty
        else {
            throw XCTSkip("Saved password for c4-local not available in keychain")
        }

        let details = ConnectionDetails(
            savedConnectionID: saved.id,
            username: saved.defaultUsername,
            password: pwd,
            tns: saved.name,
            connectionRole: .regular
        )
        let cfg = try OracleEndpoint.configuration(for: details, store: store, keychain: keychain)
        var logger = Logging.Logger(label: "macintora.tests.script.live.conn")
        logger.logLevel = .notice
        return try await OracleConnection.connect(
            on: OracleEventLoopGroup.shared.next(),
            configuration: cfg,
            id: Int.random(in: 1...Int.max),
            logger: logger
        )
    }
}
