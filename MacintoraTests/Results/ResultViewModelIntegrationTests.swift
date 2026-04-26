import XCTest
@testable import Macintora

/// Integration test that drives `ResultViewModel` against a live Oracle
/// connection, reproducing the exact user-reported sequence:
///
///   1. `select * from user_objects order by 1;`   (small — works)
///   2. `select * from all_objects;`              (large — Bug A: used to hang)
///   3. press stop/start to cancel                 (Bug B: activeQuery stuck)
///   4. run another query                          (Bug B: used to hang)
///   5. disconnect                                 (Bug B: used to crash)
///
/// All steps run through a single document instance / single connection, which
/// matches the user's actual workflow and avoids multi-process Oracle-NIO
/// state-machine races that a 4-test-per-process suite would trigger.
///
/// Requires the fixture at `~/Documents/macintora/local.macintora` and a
/// reachable Oracle matching its TNS alias. When the fixture is missing the
/// test skips; when Oracle is unreachable the initial connect times out and
/// the test skips.
@MainActor
final class ResultViewModelIntegrationTests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath: "/Users/ilia/Documents/macintora/local.macintora")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.fixtureURL.path),
            "Fixture document required for integration test: \(Self.fixtureURL.path)"
        )
    }

    func test_userRepro_queriesCancelDisconnect() async throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let doc = try await Task.detached { try MainDocumentVM(documentData: data) }.value

        // Spin up a per-test connection store + Keychain so the fixture's
        // `tns` resolves through the new connection-manager flow. The fixture
        // doc carries `tns: <alias>`; we materialise a SavedConnection from
        // tnsnames.ora at the user's standard path.
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "macintora-int-\(UUID().uuidString).json")
        let store = ConnectionStore(storeURL: storeURL)
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let keychain = KeychainService(service: "com.iliasazonov.macintora.tests.\(UUID().uuidString)")
        let tnsPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.oracle/tnsnames.ora"
        store.importFromTnsnames(at: tnsPath)

        doc.prepareOnAppear(store: store, keychain: keychain)
        doc.connect(store: store, keychain: keychain)

        // 0. Wait for the connection; skip if Oracle is unreachable.
        let connectDeadline = Date().addingTimeInterval(10)
        while doc.isConnected != .connected {
            if Date() > connectDeadline {
                doc.disconnect()
                try await Task.sleep(for: .milliseconds(500))
                try XCTSkipIf(true, "Could not connect to Oracle fixture within 10s — skipping integration test")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        let vm = try XCTUnwrap(doc.resultsController?.results["current"])
        let conn = try XCTUnwrap(doc.conn)

        // 1. user_objects — should succeed.
        vm.currentSql = "select * from user_objects order by 1"
        vm.promptForBindsAndExecute(for: RunnableSQL(sql: vm.currentSql), using: conn)
        try await awaitIdle(doc.resultsController!, timeout: 10, label: "user_objects")
        XCTAssertFalse(vm.isFailed, "user_objects unexpectedly failed: \(vm.runningLog.last?.text ?? "?")")

        // 2. all_objects WITH order by — exact user-reported repro that
        //    crashed oracle-nio's state machine when DBMS_OUTPUT was enabled
        //    per query.
        vm.currentSql = "select * from all_objects order by 1"
        vm.promptForBindsAndExecute(for: RunnableSQL(sql: vm.currentSql), using: conn)
        try await awaitIdle(doc.resultsController!, timeout: 15, label: "all_objects order by 1")
        XCTAssertFalse(vm.isFailed, "all_objects unexpectedly failed: \(vm.runningLog.last?.text ?? "?")")
        XCTAssertGreaterThan(vm.rows.count, 0, "all_objects returned no rows")
        XCTAssertTrue(vm.hasActiveQuery, "Expected activeQuery to be held after cap-hit for fetchMore support")

        // 3. cancel — Bug B: activeQuery must drop so the connection is idle.
        vm.cancel()
        XCTAssertFalse(vm.hasActiveQuery, "Bug B: cancel() must clear activeQuery")

        // 4. subsequent query — Bug B: used to hang because stream still open.
        vm.currentSql = "select 1 from dual"
        vm.promptForBindsAndExecute(for: RunnableSQL(sql: vm.currentSql), using: conn)
        try await awaitIdle(doc.resultsController!, timeout: 5, label: "dual-after-cancel")
        XCTAssertFalse(vm.isFailed, "post-cancel query failed: \(vm.runningLog.last?.text ?? "?")")
        XCTAssertEqual(vm.rows.count, 1, "select 1 from dual should return exactly one row")

        // 5. large query then disconnect mid-stream — Bug B: used to crash.
        vm.currentSql = "select * from all_objects order by 1"
        vm.promptForBindsAndExecute(for: RunnableSQL(sql: vm.currentSql), using: conn)
        try await awaitIdle(doc.resultsController!, timeout: 15, label: "all_objects order by 1 (pre-disconnect)")

        doc.disconnect()
        let disconnectDeadline = Date().addingTimeInterval(5)
        while doc.isConnected != .disconnected {
            if Date() > disconnectDeadline {
                XCTFail("disconnect() did not reach .disconnected within 5s")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(doc.conn, "conn should be nil after disconnect")
        // If we're still alive here the process didn't crash — that's the
        // primary Bug B assertion.
    }

    // MARK: - Helpers

    private func awaitIdle(
        _ controller: ResultsController,
        timeout: TimeInterval,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.isExecuting {
            if Date() > deadline {
                XCTFail(
                    "[\(label)] did not become idle within \(timeout)s — hang reproduced",
                    file: file,
                    line: line
                )
                controller.results["current"]?.cancel()
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
