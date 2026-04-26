import XCTest
@testable import Macintora

/// Migration tests for documents written before the connection-manager
/// overhaul. Pre-overhaul documents carry only `tns: <alias>` (no
/// savedConnectionID, no host/port). When they're opened, the document VM is
/// expected to look up the alias in the new `ConnectionStore` and stamp the
/// document with the matching saved-connection ID — without writing to disk
/// until the user saves.
@MainActor
final class LegacyDocumentMigrationTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConnectionStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "macintora-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConnectionStore(storeURL: tempDir.appending(path: "connections.json", directoryHint: .notDirectory))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func test_legacyDocAnchorsToMatchingSavedConnection() async throws {
        let saved = SavedConnection(name: "PROD", host: "h", service: .serviceName("prod"))
        store.upsert(saved)

        // Encode a "legacy" document — only tns set.
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "text": "select 1 from dual;",
          "preferences": {},
          "connectionDetails": {
            "tns": "PROD",
            "username": "scott",
            "connectionRole": "regular"
          }
        }
        """
        let doc = try MainDocumentVM(documentData: Data(legacyJSON.utf8))
        XCTAssertNil(doc.mainConnection.mainConnDetails.savedConnectionID)

        doc.prepareOnAppear(store: store)

        XCTAssertEqual(doc.mainConnection.mainConnDetails.savedConnectionID, saved.id)
        XCTAssertEqual(doc.mainConnection.mainConnDetails.tns, "PROD")
    }

    func test_legacyDocWithUnknownAliasShowsBanner() throws {
        // Store empty; legacy doc references "GHOST" — should remain
        // un-anchored so the UI can show a banner.
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "text": "",
          "preferences": {},
          "connectionDetails": {
            "tns": "GHOST",
            "username": "u",
            "connectionRole": "regular"
          }
        }
        """
        let doc = try MainDocumentVM(documentData: Data(legacyJSON.utf8))
        doc.prepareOnAppear(store: store)
        XCTAssertNil(doc.mainConnection.mainConnDetails.savedConnectionID)
        XCTAssertEqual(doc.mainConnection.mainConnDetails.tns, "GHOST")
    }

    func test_legacyDocCaseInsensitiveMatch() throws {
        let saved = SavedConnection(name: "Stage", host: "h", service: .serviceName("s"))
        store.upsert(saved)
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "text": "",
          "preferences": {},
          "connectionDetails": {
            "tns": "STAGE",
            "username": "u",
            "connectionRole": "regular"
          }
        }
        """
        let doc = try MainDocumentVM(documentData: Data(legacyJSON.utf8))
        doc.prepareOnAppear(store: store)
        XCTAssertEqual(doc.mainConnection.mainConnDetails.savedConnectionID, saved.id)
    }
}
