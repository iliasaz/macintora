import XCTest
@testable import Macintora

final class SessionRestorerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "Macintora.SessionRestorerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "macintora-session-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeRestorer() -> SessionRestorer {
        SessionRestorer(defaults: defaults, fileManager: .default)
    }

    private func touch(_ name: String) throws -> URL {
        let url = tempDir.appending(path: name, directoryHint: .notDirectory)
        try Data().write(to: url)
        return url
    }

    func test_freshDefaultsHasNoRestorableURLs() {
        XCTAssertEqual(makeRestorer().restorableURLs(), [])
    }

    func test_saveAndRestoreRoundTrip() throws {
        let a = try touch("a.macintora")
        let b = try touch("b.macintora")
        let c = try touch("c.macintora")

        let restorer = makeRestorer()
        restorer.saveSession(urls: [a, b, c])

        let restored = restorer.restorableURLs()
        XCTAssertEqual(restored.map(\.standardizedFileURL),
                       [a, b, c].map(\.standardizedFileURL))
    }

    func test_missingFilesFiltered() throws {
        let a = try touch("a.macintora")
        let b = try touch("b.macintora")

        let restorer = makeRestorer()
        restorer.saveSession(urls: [a, b])
        try FileManager.default.removeItem(at: a)

        let restored = restorer.restorableURLs()
        XCTAssertEqual(restored.map(\.standardizedFileURL),
                       [b.standardizedFileURL])
    }

    func test_duplicatesDeduped() throws {
        let a = try touch("a.macintora")
        // Build a non-standardized variant via a `.` segment so dedupe must
        // canonicalize before comparing.
        let aDup = tempDir
            .appending(path: ".", directoryHint: .isDirectory)
            .appending(path: "a.macintora", directoryHint: .notDirectory)

        let restorer = makeRestorer()
        restorer.saveSession(urls: [a, aDup, a])

        XCTAssertEqual(restorer.restorableURLs().count, 1)
    }

    func test_emptyListClears() throws {
        let a = try touch("a.macintora")
        let restorer = makeRestorer()
        restorer.saveSession(urls: [a])
        XCTAssertEqual(restorer.restorableURLs().count, 1)

        restorer.saveSession(urls: [])
        XCTAssertEqual(restorer.restorableURLs(), [])
    }

    // MARK: - LaunchGuard

    func test_launchGuard_freshDefaults_reportsCleanPriorRun() {
        var guardian = LaunchGuard(defaults: defaults)
        XCTAssertTrue(guardian.beginLaunch(),
                      "Fresh defaults must mean previous run was clean (no flag set).")
    }

    func test_launchGuard_dirtyFlag_reportsCrashedPriorRun() {
        // Simulate a previous launch that set the flag and never cleared
        // it (i.e., the app crashed before terminate or grace clear).
        defaults.set(true, forKey: LaunchGuard.defaultsKey)
        var guardian = LaunchGuard(defaults: defaults)
        XCTAssertFalse(guardian.beginLaunch(),
                       "Dirty flag must signal that previous run did not exit cleanly.")
    }

    func test_launchGuard_beginLaunch_sets_flag_for_next_run() {
        var guardian = LaunchGuard(defaults: defaults)
        _ = guardian.beginLaunch()
        XCTAssertTrue(defaults.bool(forKey: LaunchGuard.defaultsKey),
                      "beginLaunch must always set the flag so a crash leaves it dirty.")
    }

    func test_launchGuard_markCleanShutdown_clearsFlag() {
        var guardian = LaunchGuard(defaults: defaults)
        _ = guardian.beginLaunch()
        guardian.markCleanShutdown()
        XCTAssertFalse(defaults.bool(forKey: LaunchGuard.defaultsKey))
    }

    func test_launchGuard_cleanCycle_then_dirtyCycle() {
        // Run 1: clean.
        var run1 = LaunchGuard(defaults: defaults)
        XCTAssertTrue(run1.beginLaunch())
        run1.markCleanShutdown()

        // Run 2: clean prior run → restore proceeds, then crashes (no
        // markCleanShutdown call).
        var run2 = LaunchGuard(defaults: defaults)
        XCTAssertTrue(run2.beginLaunch())
        // (no markCleanShutdown — simulated crash)

        // Run 3: prior dirty → restore must be skipped.
        var run3 = LaunchGuard(defaults: defaults)
        XCTAssertFalse(run3.beginLaunch())
        run3.markCleanShutdown()

        // Run 4: prior clean again → restore proceeds.
        var run4 = LaunchGuard(defaults: defaults)
        XCTAssertTrue(run4.beginLaunch())
    }
}
