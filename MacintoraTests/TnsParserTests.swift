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

    // MARK: - Real-world patterns from user's tnsnames.ora

    /// Quoted DN with embedded `=` and `,` plus shell-style `${TNS_ADMIN}`
    /// substitution must not break parsing of the whole file.
    func test_walletEntryWithQuotedDN() {
        let file = """
        ohfadw2020_high=(description=(retry_count=20)(retry_delay=3)(address=(https_proxy=www-proxy-hqdc.us.oracle.com)(https_proxy_port=80)(protocol=tcps)(port=1522)(host=adb.us-ashburn-1.oraclecloud.com))(connect_data=(service_name=m8yollkmjgtvmcu_ohfadw2020_high.adwc.oraclecloud.com))(security=(ssl_server_cert_dn="CN=adwc.uscom-east-1.oraclecloud.com,OU=Oracle BMCS US,O=Oracle Corporation,L=Redwood City,ST=California,C=US")(MY_WALLET_DIRECTORY=${TNS_ADMIN}/Wallet_OHFADW2020)))
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].alias, "ohfadw2020_high")
        XCTAssertEqual(entries[0].host, "adb.us-ashburn-1.oraclecloud.com")
        XCTAssertEqual(entries[0].port, 1522)
        XCTAssertEqual(entries[0].serviceName, "m8yollkmjgtvmcu_ohfadw2020_high.adwc.oraclecloud.com")
    }

    func test_descriptionListLoadBalanceFailover() {
        let file = """
        merck2=(DESCRIPTION_LIST=(LOAD_BALANCE=YES)(FAILOVER=YES)(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=h1)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=ebs_MERCK2)(INSTANCE_NAME=MERCK2C1)))(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=h2)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=ebs_MERCK2)(INSTANCE_NAME=MERCK2C2))))
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].alias, "merck2")
        XCTAssertEqual(entries[0].host, "h1") // first address in list
        XCTAssertEqual(entries[0].serviceName, "ebs_MERCK2")
    }

    func test_brokenEntryDoesNotPoisonNeighbours() {
        // Middle entry has unbalanced parens; bookends should still parse.
        let file = """
        good1=(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=h1)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=s1)))
        broken=(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=oops)(PORT=1521)
        good2=(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=h2)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=s2)))
        """
        let entries = TnsParser.parse(file)
        let aliases = entries.map(\.alias)
        XCTAssertTrue(aliases.contains("good1"))
        XCTAssertTrue(aliases.contains("good2"))
    }

    /// Exercise the full real-world fixture to verify the parser doesn't
    /// silently drop most entries. We don't pin to an exact count because
    /// the file evolves, but it should be far above the legacy parser's
    /// "few" output.
    func test_realWorldUserFixtureParsesMost() {
        let path = "/Users/ilia/Desktop/oracle/network/admin/tnsnames.ora"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            // Test is opportunistic — only runs on the dev's machine.
            return
        }
        let entries = TnsParser.parse(contents)
        // The file has ~90 entries; demand at least 60 to catch regressions
        // where we silently drop bulk content again.
        XCTAssertGreaterThan(entries.count, 60, "Expected most entries to parse, got \(entries.count)")
        XCTAssertNotNil(entries.first(where: { $0.alias == "ohfadw2020_high" }), "wallet entry with quoted DN should parse")
    }

    func test_quotedScalarValueDoesNotBreakSubsequentChildren() {
        let file = """
        x=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=s))(SECURITY=(ssl_server_cert_dn="CN=foo,OU=bar")(EXTRA=baz)))
        """
        let entries = TnsParser.parse(file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].host, "h")
        XCTAssertEqual(entries[0].serviceName, "s")
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
