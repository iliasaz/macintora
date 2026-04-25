import XCTest
@testable import Macintora

final class SavedConnectionTests: XCTestCase {

    func test_codableRoundTrip_serviceName() throws {
        let original = SavedConnection(
            name: "PROD",
            host: "db.internal",
            port: 1521,
            service: .serviceName("orcl.example.com"),
            defaultUsername: "scott",
            defaultRole: .regular,
            tls: .disabled,
            savePasswordInKeychain: true,
            notes: "primary"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedConnection.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_codableRoundTrip_sid() throws {
        let original = SavedConnection(
            name: "LEGACY",
            host: "h",
            port: 1522,
            service: .sid("orcl"),
            defaultRole: .sysDBA
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(SavedConnection.self, from: data)
        XCTAssertEqual(back.service, .sid("orcl"))
        XCTAssertEqual(back.defaultRole, .sysDBA)
    }

    func test_codableRoundTrip_walletTLS() throws {
        let original = SavedConnection(
            name: "ATP",
            host: "adb.us-ashburn-1.oraclecloud.com",
            port: 1522,
            service: .serviceName("atp_high"),
            tls: .wallet(folderPath: "/Users/me/wallet")
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(SavedConnection.self, from: data)
        XCTAssertEqual(back.tls, .wallet(folderPath: "/Users/me/wallet"))
    }

    func test_initFromTnsEntry_serviceName() {
        let entry = TnsEntry(alias: "STAGE", host: "h", port: 1521, serviceName: "stg")
        let conn = SavedConnection(from: entry)
        XCTAssertEqual(conn.name, "STAGE")
        XCTAssertEqual(conn.host, "h")
        XCTAssertEqual(conn.port, 1521)
        XCTAssertEqual(conn.service, .serviceName("stg"))
    }

    func test_initFromTnsEntry_sidFallback() {
        let entry = TnsEntry(alias: "OLD", host: "h", port: 1522, serviceName: nil, sid: "legacy")
        let conn = SavedConnection(from: entry)
        XCTAssertEqual(conn.service, .sid("legacy"))
    }

    func test_initFromTnsEntry_emptyServiceFallsBackToAlias() {
        let entry = TnsEntry(alias: "NAMED", host: "h", port: 1521, serviceName: nil, sid: nil)
        let conn = SavedConnection(from: entry)
        XCTAssertEqual(conn.service, .serviceName("NAMED"))
    }
}
