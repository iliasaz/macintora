import XCTest
@testable import Macintora

/// Verifies that `ConnectionDetails` keeps its post-overhaul Codable contract:
/// password is session-only, never persisted; `savedConnectionID` round-trips;
/// pre-overhaul documents (no `savedConnectionID`, only `tns`) decode cleanly.
final class ConnectionDetailsCodableTests: XCTestCase {

    func test_passwordIsNotEncoded() throws {
        let details = ConnectionDetails(
            savedConnectionID: UUID(),
            username: "u",
            password: "secret-do-not-leak",
            tns: "PROD",
            connectionRole: .regular
        )
        let data = try JSONEncoder().encode(details)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("password"), "password key should not appear in JSON")
        XCTAssertFalse(json.contains("secret-do-not-leak"), "password value must not be persisted")
    }

    func test_decodingBlanksPassword() throws {
        let original = ConnectionDetails(
            savedConnectionID: UUID(),
            username: "u",
            password: "session",
            tns: "PROD",
            connectionRole: .sysDBA
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionDetails.self, from: data)
        XCTAssertEqual(decoded.savedConnectionID, original.savedConnectionID)
        XCTAssertEqual(decoded.username, "u")
        XCTAssertEqual(decoded.tns, "PROD")
        XCTAssertEqual(decoded.connectionRole, .sysDBA)
        XCTAssertEqual(decoded.password, "", "password should never come back from disk")
    }

    func test_legacyDocumentDecodes() throws {
        // Pre-overhaul shape: tns, username, connectionRole, plus the now-discarded password.
        let legacyJSON = """
        {
          "tns": "LEGACY",
          "username": "scott",
          "password": "tiger",
          "connectionRole": "regular"
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(ConnectionDetails.self, from: data)
        XCTAssertNil(decoded.savedConnectionID)
        XCTAssertEqual(decoded.tns, "LEGACY")
        XCTAssertEqual(decoded.username, "scott")
        XCTAssertEqual(decoded.connectionRole, .regular)
        XCTAssertEqual(decoded.password, "")
    }

    func test_savedConnectionIDRoundTrips() throws {
        let id = UUID()
        let original = ConnectionDetails(savedConnectionID: id, tns: "PROD")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionDetails.self, from: data)
        XCTAssertEqual(decoded.savedConnectionID, id)
    }
}
