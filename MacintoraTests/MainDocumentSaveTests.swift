import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import Macintora

/// Exercises `ReferenceFileDocument.snapshot(contentType:)` end-to-end. Reproduces
/// the save-path crash that surfaced after turning on `InferIsolatedConformances` —
/// SwiftUI invokes `snapshot` off the MainActor executor, so the implementation
/// must be callable from any isolation.
final class MainDocumentSaveTests: XCTestCase {

    @MainActor
    func test_snapshotRoundTripsThroughJSON() throws {
        let doc = MainDocumentVM(text: "select 42 from dual;")
        doc.mainConnection.mainConnDetails.username = "alice"
        doc.mainConnection.mainConnDetails.tns = "PROD"
        doc.mainConnection.mainConnDetails.connectionRole = .sysDBA

        let snapshot = try doc.snapshot(contentType: .macora)
        XCTAssertEqual(snapshot.text, "select 42 from dual;")
        XCTAssertEqual(snapshot.connectionDetails.username, "alice")
        XCTAssertEqual(snapshot.connectionDetails.tns, "PROD")
        XCTAssertEqual(snapshot.connectionDetails.connectionRole, .sysDBA)

        // Round-trip the snapshot to a file and back to prove the wire format is stable.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macintora-save-\(UUID().uuidString).macintora")
        let encoded = try JSONEncoder().encode(snapshot)
        try encoded.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let raw = try Data(contentsOf: tempURL)
        let decoded = try JSONDecoder().decode(MainModel.self, from: raw)
        XCTAssertEqual(decoded.text, "select 42 from dual;")
        XCTAssertEqual(decoded.connectionDetails.username, "alice")
        XCTAssertEqual(decoded.connectionDetails.tns, "PROD")
    }

    /// The regression test for the original crash. Calling snapshot from a
    /// `Task.detached` mirrors what SwiftUI's file-coordination machinery does
    /// during save/autosave. It must not trap, regardless of actor isolation.
    func test_snapshotFromNonMainActor() async throws {
        let doc = await MainDocumentVM(text: "off-main test")

        let snap = try await Task.detached(priority: .utility) {
            try doc.snapshot(contentType: .macora)
        }.value

        XCTAssertEqual(snap.text, "off-main test")
    }

    /// Snapshot's returned value must reflect writes to the document even when the
    /// reader races on a different thread. Exercises the Mutex-backed store that
    /// replaced the old `@MainActor` stored properties.
    func test_snapshotReflectsMainActorWrites() async throws {
        let doc = await MainDocumentVM(text: "initial")

        await MainActor.run {
            doc.model.text = "updated"
            doc.mainConnection.mainConnDetails.username = "bob"
        }

        let snap = try await Task.detached(priority: .utility) {
            try doc.snapshot(contentType: .macora)
        }.value
        XCTAssertEqual(snap.text, "updated")
        XCTAssertEqual(snap.connectionDetails.username, "bob")
    }
}
