import XCTest
@testable import Macintora

final class TnsParserTests: XCTestCase {
    func test_simpleServiceName() {
        let file = """
        ORCL =
          (DESCRIPTION =
            (ADDRESS = (PROTOCOL = TCP)(HOST = host1)(PORT = 1521))
            (CONNECT_DATA = (SERVICE_NAME = orcl.example.com))
          )
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].alias, "ORCL")
        XCTAssertEqual(entries[0].host, "host1")
        XCTAssertEqual(entries[0].port, 1521)
        XCTAssertEqual(entries[0].serviceName, "orcl.example.com")
        XCTAssertNil(entries[0].sid)
    }

    func test_sidForm() {
        let file = """
        OLD =
          (DESCRIPTION =
            (ADDRESS = (PROTOCOL = TCP)(HOST = host2)(PORT = 1522))
            (CONNECT_DATA = (SID = legacy))
          )
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].alias, "OLD")
        XCTAssertEqual(entries[0].host, "host2")
        XCTAssertEqual(entries[0].port, 1522)
        XCTAssertNil(entries[0].serviceName)
        XCTAssertEqual(entries[0].sid, "legacy")
    }

    func test_withComments() {
        let file = """
        # this is a comment
        ORCL =
          (DESCRIPTION =
            # address below
            (ADDRESS = (PROTOCOL = TCP)(HOST = host3)(PORT = 1521)) # trailing
            (CONNECT_DATA = (SERVICE_NAME = mydb))
          )
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].host, "host3")
        XCTAssertEqual(entries[0].serviceName, "mydb")
    }

    func test_multipleAliases() {
        let file = """
        A =
          (DESCRIPTION =
            (ADDRESS = (HOST = ha)(PORT = 1521))
            (CONNECT_DATA = (SERVICE_NAME = a))
          )

        B =
          (DESCRIPTION =
            (ADDRESS = (HOST = hb)(PORT = 1522))
            (CONNECT_DATA = (SERVICE_NAME = b))
          )
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.alias)), ["A", "B"])
        let a = entries.first(where: { $0.alias == "A" })!
        XCTAssertEqual(a.host, "ha")
        XCTAssertEqual(a.serviceName, "a")
        let b = entries.first(where: { $0.alias == "B" })!
        XCTAssertEqual(b.host, "hb")
        XCTAssertEqual(b.serviceName, "b")
    }

    func test_firstAddressOnly() {
        let file = """
        RAC =
          (DESCRIPTION =
            (ADDRESS_LIST =
              (ADDRESS = (PROTOCOL = TCP)(HOST = node1)(PORT = 1521))
              (ADDRESS = (PROTOCOL = TCP)(HOST = node2)(PORT = 1521))
            )
            (CONNECT_DATA = (SERVICE_NAME = rac_svc))
          )
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].host, "node1")
        XCTAssertEqual(entries[0].serviceName, "rac_svc")
    }

    func test_malformedEntryIsSkipped() {
        let file = """
        BAD =
          # missing body

        GOOD =
          (DESCRIPTION =
            (ADDRESS = (HOST = h)(PORT = 1521))
            (CONNECT_DATA = (SERVICE_NAME = s))
          )
        """
        let entries = TnsParser.parse(file)
        // BAD has no host/port so it's dropped
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].alias, "GOOD")
    }

    func test_emptyInput() {
        XCTAssertEqual(TnsParser.parse("").count, 0)
        XCTAssertEqual(TnsParser.parse("   \n\n  ").count, 0)
    }

    // MARK: - parseDescriptor

    func test_parseDescriptor_serviceName() {
        let entry = TnsParser.parseDescriptor(
            "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h1)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=svc)))"
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.host, "h1")
        XCTAssertEqual(entry?.port, 1521)
        XCTAssertEqual(entry?.serviceName, "svc")
    }

    func test_parseDescriptor_sid() {
        let entry = TnsParser.parseDescriptor(
            "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h)(PORT=1521))(CONNECT_DATA=(SID=L)))"
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.sid, "L")
    }

    func test_parseDescriptor_returnsNilForGarbage() {
        XCTAssertNil(TnsParser.parseDescriptor("totally not a descriptor"))
        XCTAssertNil(TnsParser.parseDescriptor(""))
    }

    func test_parseDescriptor_pickFirstAddress() {
        let entry = TnsParser.parseDescriptor("""
        (DESCRIPTION=
          (ADDRESS_LIST=
            (ADDRESS=(PROTOCOL=TCP)(HOST=node1)(PORT=1521))
            (ADDRESS=(PROTOCOL=TCP)(HOST=node2)(PORT=1521)))
          (CONNECT_DATA=(SERVICE_NAME=rac_svc)))
        """)
        XCTAssertEqual(entry?.host, "node1")
        XCTAssertEqual(entry?.serviceName, "rac_svc")
    }
}
