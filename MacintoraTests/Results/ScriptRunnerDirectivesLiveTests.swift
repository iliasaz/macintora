//
//  ScriptRunnerDirectivesLiveTests.swift
//  MacintoraTests
//
//  c4-local integration coverage of Phase 6 directives:
//    - SET SERVEROUTPUT ON/OFF actually toggles DBMS_OUTPUT capture.
//    - WHENEVER SQLERROR EXIT halts the script on the first failing unit.
//    - DEFINE / & substitution flows through to the resolved SQL.
//

import XCTest
import OracleNIO
import Logging
@testable import Macintora

@MainActor
final class ScriptRunnerDirectivesLiveTests: XCTestCase {

    func test_set_serveroutput_off_suppresses_dbmsOutput() async throws {
        let conn = try await openLiveConnection()
        defer { Task { try? await conn.close() } }

        // Drive the executor directly with `dbmsOutputEnabled: false`, mimicking
        // what `ResultsController.startScriptExecution` does when the env's
        // final `serverOutput` is `false`.
        let script = """
        BEGIN
          DBMS_OUTPUT.PUT_LINE('quiet');
        END;
        /
        """
        let units = ScriptLexer.split(script).units
        let executor = OracleScriptExecutor(
            conn: conn,
            logger: Logging.Logger(label: "macintora.tests.directives"),
            dbmsOutputEnabled: false
        )
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())

        var dbmsLines: [String] = []
        for await event in runner.start() {
            if case .unitFinished(_, let r) = event,
               case .statementSucceeded(_, let lines, _) = r.outcome {
                dbmsLines.append(contentsOf: lines)
            }
        }
        XCTAssertTrue(dbmsLines.isEmpty, "expected no DBMS_OUTPUT when serveroutput off; got \(dbmsLines)")
    }

    func test_whenever_sqlerror_exit_halts_on_failure() async throws {
        let conn = try await openLiveConnection()
        defer { Task { try? await conn.close() } }

        let script = """
        SELECT 1 FROM dual;
        SELECT * FROM macintora_no_such_table;
        SELECT 2 FROM dual;
        """
        let units = ScriptLexer.split(script).units
        let executor = OracleScriptExecutor(
            conn: conn,
            logger: Logging.Logger(label: "macintora.tests.directives")
        )
        // The runner halts on error when env.whenever is `.exit(...)`.
        let env = SqlPlusEnvironment()
        env.whenever = .exit(.failure, commitOrRollback: nil)
        let runner = ScriptRunner(units: units, executor: executor, env: env)

        var observed: [(Int, UnitResult.Outcome)] = []
        for await event in runner.start() {
            if case .unitFinished(let i, let r) = event {
                observed.append((i, r.outcome))
            }
        }
        XCTAssertEqual(observed.count, 2, "WHENEVER EXIT should halt after the failing unit; saw \(observed.count) outcomes")
        if case .statementSucceeded = observed.first?.1 {} else {
            XCTFail("first unit should have succeeded")
        }
        if case .statementFailed = observed.last?.1 {} else {
            XCTFail("second unit should have failed")
        }
    }

    func test_define_substitutes_into_subsequent_select() async throws {
        let conn = try await openLiveConnection()
        defer { Task { try? await conn.close() } }

        // The runner applies DEFINE inline as it walks the units, so the
        // subsequent SELECT picks up the value via SubstitutionResolver.
        let units = ScriptLexer.split("""
        DEFINE thing = USER
        SELECT &thing AS who FROM dual;
        """).units

        let executor = OracleScriptExecutor(
            conn: conn,
            logger: Logging.Logger(label: "macintora.tests.directives")
        )
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())

        var rows: [[String]] = []
        for await event in runner.start() {
            if case .unitFinished(_, let r) = event,
               case .statementSucceeded(_, _, let preview) = r.outcome,
               let preview {
                rows.append(contentsOf: preview.rows)
            }
        }
        XCTAssertEqual(rows.count, 1, "expected one row from substituted SELECT")
    }

    // MARK: - Connection helper

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
        var logger = Logging.Logger(label: "macintora.tests.directives.conn")
        logger.logLevel = .notice
        return try await OracleConnection.connect(
            on: OracleEventLoopGroup.shared.next(),
            configuration: cfg,
            id: Int.random(in: 1...Int.max),
            logger: logger
        )
    }
}
