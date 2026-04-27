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
}
