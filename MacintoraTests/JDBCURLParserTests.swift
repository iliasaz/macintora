import XCTest
@testable import Macintora

final class JDBCURLParserTests: XCTestCase {

    func test_thinSlashServiceName() throws {
        let r = try JDBCURLParser.parse("jdbc:oracle:thin:@db.internal:1521/orcl")
        XCTAssertEqual(r.host, "db.internal")
        XCTAssertEqual(r.port, 1521)
        XCTAssertEqual(r.service, .serviceName("orcl"))
        XCTAssertEqual(r.tls, .disabled)
    }

    func test_thinDoubleSlashServiceName() throws {
        let r = try JDBCURLParser.parse("jdbc:oracle:thin:@//db.internal:1521/orcl")
        XCTAssertEqual(r.host, "db.internal")
        XCTAssertEqual(r.port, 1521)
        XCTAssertEqual(r.service, .serviceName("orcl"))
        XCTAssertEqual(r.tls, .disabled)
    }

    func test_thinSidLegacy() throws {
        let r = try JDBCURLParser.parse("jdbc:oracle:thin:@db.internal:1522:LEG")
        XCTAssertEqual(r.host, "db.internal")
        XCTAssertEqual(r.port, 1522)
        XCTAssertEqual(r.service, .sid("LEG"))
    }

    func test_tcpsScheme() throws {
        let r = try JDBCURLParser.parse("jdbc:oracle:thin:@tcps://adb.us-ashburn-1.oraclecloud.com:1522/atp_high")
        XCTAssertEqual(r.host, "adb.us-ashburn-1.oraclecloud.com")
        XCTAssertEqual(r.port, 1522)
        XCTAssertEqual(r.service, .serviceName("atp_high"))
        XCTAssertEqual(r.tls, .system)
    }

    func test_payloadWithoutPrefix() throws {
        // Users often paste just the @-payload from documentation.
        let r = try JDBCURLParser.parse("@host:1521/svc")
        XCTAssertEqual(r.host, "host")
        XCTAssertEqual(r.service, .serviceName("svc"))
    }

    func test_descriptorForm() throws {
        let r = try JDBCURLParser.parse(
            "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h1)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=svc)))"
        )
        XCTAssertEqual(r.host, "h1")
        XCTAssertEqual(r.port, 1521)
        XCTAssertEqual(r.service, .serviceName("svc"))
        XCTAssertEqual(r.tls, .disabled)
    }

    func test_descriptorTcpsImpliesTLS() throws {
        let r = try JDBCURLParser.parse(
            "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=h)(PORT=2484))(CONNECT_DATA=(SERVICE_NAME=s)))"
        )
        XCTAssertEqual(r.tls, .system)
    }

    func test_defaultPort() throws {
        let r = try JDBCURLParser.parse("@host/svc")
        XCTAssertEqual(r.port, 1521)
    }

    func test_emptyThrows() {
        XCTAssertThrowsError(try JDBCURLParser.parse(""))
        XCTAssertThrowsError(try JDBCURLParser.parse("   "))
    }

    func test_missingServiceThrows() {
        XCTAssertThrowsError(try JDBCURLParser.parse("@host:1521"))
        XCTAssertThrowsError(try JDBCURLParser.parse("jdbc:oracle:thin:@host:1521/"))
    }

    func test_unrecognizedSchemeThrows() {
        XCTAssertThrowsError(try JDBCURLParser.parse("postgres://user@host/db"))
    }

    func test_malformedPortThrows() {
        XCTAssertThrowsError(try JDBCURLParser.parse("@host:notaport/svc"))
    }
}
