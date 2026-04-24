import XCTest
@testable import Macintora

final class OracleEndpointTests: XCTestCase {
    func test_resolveKnownAlias() throws {
        let entry = TnsEntry(alias: "PROD", host: "h1", port: 1521, serviceName: "prod_svc")
        let details = ConnectionDetails(username: "u", password: "p", tns: "prod", connectionRole: .regular)
        let config = try OracleEndpoint.configuration(for: details, aliases: [entry])
        XCTAssertEqual(config.host, "h1")
        XCTAssertEqual(config.port, 1521)
        XCTAssertEqual(config.mode, .default)
    }

    func test_resolveKnownAliasCaseInsensitive() throws {
        let entry = TnsEntry(alias: "Prod", host: "h", port: 1521, serviceName: "s")
        let details = ConnectionDetails(username: "u", password: "p", tns: "PROD", connectionRole: .regular)
        let config = try OracleEndpoint.configuration(for: details, aliases: [entry])
        XCTAssertEqual(config.host, "h")
    }

    func test_sysDBAMode() throws {
        let entry = TnsEntry(alias: "DB", host: "h", port: 1521, serviceName: "s")
        let details = ConnectionDetails(username: "u", password: "p", tns: "DB", connectionRole: .sysDBA)
        let config = try OracleEndpoint.configuration(for: details, aliases: [entry])
        XCTAssertEqual(config.mode, .sysDBA)
    }

    func test_manualEndpointHostPortService() throws {
        let entry = try OracleEndpoint.parseManualEndpoint("db.internal:1522/myservice")
        XCTAssertEqual(entry.host, "db.internal")
        XCTAssertEqual(entry.port, 1522)
        XCTAssertEqual(entry.serviceName, "myservice")
    }

    func test_manualEndpointDefaultPort() throws {
        let entry = try OracleEndpoint.parseManualEndpoint("db.internal/svc")
        XCTAssertEqual(entry.host, "db.internal")
        XCTAssertEqual(entry.port, 1521)
        XCTAssertEqual(entry.serviceName, "svc")
    }

    func test_manualEndpointRequiresService() {
        XCTAssertThrowsError(try OracleEndpoint.parseManualEndpoint("db.internal:1521"))
        XCTAssertThrowsError(try OracleEndpoint.parseManualEndpoint(""))
    }

    func test_unknownAliasFallsThroughToManualParseAndFails() {
        let details = ConnectionDetails(username: "u", password: "p", tns: "bogus", connectionRole: .regular)
        XCTAssertThrowsError(try OracleEndpoint.configuration(for: details, aliases: []))
    }

    func test_sidFromAlias() throws {
        let entry = TnsEntry(alias: "SID_ONLY", host: "h", port: 1521, serviceName: nil, sid: "abc")
        let details = ConnectionDetails(username: "u", password: "p", tns: "sid_only", connectionRole: .regular)
        let config = try OracleEndpoint.configuration(for: details, aliases: [entry])
        XCTAssertEqual(config.host, "h")
    }
}
