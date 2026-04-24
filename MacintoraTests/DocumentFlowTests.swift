import XCTest
import UniformTypeIdentifiers
@testable import Macintora

/// End-to-end smoke tests for the primary user flow: launch → open → type →
/// save → close → reopen. Drives `MainDocumentVM` at the view-model level,
/// which is one layer below XCUITest (no AppKit event dispatch) but covers
/// every piece of state a user interaction would touch. Runs in milliseconds
/// so we can keep this in the main test suite.
///
/// For full keystroke / window simulation we'd need a separate XCUITest
/// target — that's a bigger scaffolding change; ask if you want it.
final class DocumentFlowTests: XCTestCase {

    /// "Launch app → new document → type → save to disk → close → reopen →
    /// verify all the typed content is present."
    func test_newDocumentTypeSaveReopen() async throws {
        // 1. Launch — in production, DocumentGroup constructs the VM on main.
        let doc = await MainActor.run { MainDocumentVM(text: "starting content") }
        await MainActor.run { doc.prepareOnAppear() }
        XCTAssertNotNil(doc.resultsController, "ResultsController should be wired up on appear")
        XCTAssertEqual(doc.isConnected, .disconnected)
        XCTAssertEqual(doc.model.text, "starting content")

        // 2. Simulate typing — each character is a separate main-actor write.
        let typedBody = "select owner, table_name from dba_tables where rownum < 10;\n"
        await MainActor.run {
            for char in typedBody {
                doc.model.text.append(char)
            }
        }
        XCTAssertEqual(doc.model.text, "starting content" + typedBody)

        // 3. Save — snapshot (off main, like SwiftUI) then encode to disk.
        let snapshot = try await Task.detached(priority: .utility) {
            try doc.snapshot(contentType: .macora)
        }.value
        let encoded = try JSONEncoder().encode(snapshot)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macintora-flow-\(UUID().uuidString).macintora")
        try encoded.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 4. Close — in SwiftUI this happens via window close; here the doc
        //    variable goes out of scope at the end of the test. We just make
        //    sure nothing crashes during tear-down.

        // 5. Reopen via the same init path SwiftUI uses for `File > Open`.
        let reopenData = try Data(contentsOf: tempURL)
        let reopened = try await Task.detached(priority: .utility) {
            try MainDocumentVM(documentData: reopenData)
        }.value

        // Reopened document must contain everything the user typed.
        XCTAssertEqual(reopened.model.text, "starting content" + typedBody)
    }

    /// The file open crash we just fixed: init(configuration:) being invoked
    /// off the MainActor executor. This doubles as a UX-layer regression test
    /// (document open from outside main actor must not trap).
    func test_openDocumentOffMainActorDoesNotTrap() async throws {
        let encoded = try JSONEncoder().encode(MainModel(text: "hello"))
        _ = try await Task.detached(priority: .utility) {
            try MainDocumentVM(documentData: encoded)
        }.value
    }

    /// "Change connection details before save, verify they round-trip."
    /// Mirrors what a user does via the connection sidebar.
    func test_connectionDetailsSurviveSaveReopen() async throws {
        let doc = await MainActor.run { MainDocumentVM(text: "") }

        await MainActor.run {
            doc.mainConnection.mainConnDetails.username = "iliasaz"
            doc.mainConnection.mainConnDetails.tns = "PROD.EXAMPLE.COM"
            doc.mainConnection.mainConnDetails.connectionRole = .sysDBA
        }

        let encoded = try JSONEncoder().encode(try doc.snapshot(contentType: .macora))
        let reopened = try MainDocumentVM(documentData: encoded)

        XCTAssertEqual(reopened.mainConnection.mainConnDetails.username, "iliasaz")
        XCTAssertEqual(reopened.mainConnection.mainConnDetails.tns, "PROD.EXAMPLE.COM")
        XCTAssertEqual(reopened.mainConnection.mainConnDetails.connectionRole, .sysDBA)
    }

    /// "Auto-connect documents flag survives the round-trip and is honoured on
    /// first appear." Covers the code path that previously called
    /// `connect()` from the `init(configuration:)` body.
    func test_autoConnectFlagRoundTrips() async throws {
        var seed = MainModel(text: "--")
        seed.autoConnect = true
        let encoded = try JSONEncoder().encode(seed)

        let doc = try MainDocumentVM(documentData: encoded)
        XCTAssertTrue(doc.shouldAutoConnectOnAppear, "auto-connect flag should be preserved on load")
    }
}
