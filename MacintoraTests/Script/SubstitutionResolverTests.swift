//
//  SubstitutionResolverTests.swift
//  MacintoraTests
//

import XCTest
@testable import Macintora

final class SubstitutionResolverTests: XCTestCase {

    // MARK: - scan

    func test_scan_finds_simple_references() {
        let scan = SubstitutionResolver.scan("select * from &owner.t where id = &id;")
        XCTAssertEqual(scan.names, ["OWNER", "ID"])
        XCTAssertTrue(scan.stickyNames.isEmpty)
    }

    func test_scan_distinguishes_sticky_from_simple() {
        let scan = SubstitutionResolver.scan("select &x, &&y, &x, &&y from dual;")
        XCTAssertEqual(scan.names, ["X", "Y"])
        XCTAssertEqual(scan.stickyNames, ["Y"])
    }

    func test_scan_no_references() {
        let scan = SubstitutionResolver.scan("select 1 from dual;")
        XCTAssertTrue(scan.names.isEmpty)
        XCTAssertTrue(scan.stickyNames.isEmpty)
    }

    func test_scan_ignores_lone_ampersand() {
        let scan = SubstitutionResolver.scan("select 'a & b' from dual;")
        XCTAssertTrue(scan.names.isEmpty)
    }

    func test_scan_finds_inside_strings() {
        let scan = SubstitutionResolver.scan("select 'hello &name' from dual;")
        XCTAssertEqual(scan.names, ["NAME"])
    }

    // MARK: - resolve: passthrough

    func test_resolve_no_substitutions_yields_identity_text() {
        let r = SubstitutionResolver.resolve("select 1 from dual", defines: [:])
        XCTAssertEqual(r.text, "select 1 from dual")
        XCTAssertTrue(r.missing.isEmpty)
    }

    // MARK: - resolve: simple substitution

    func test_resolve_simple_name() {
        let r = SubstitutionResolver.resolve("select * from &t;", defines: ["T": "emp"])
        XCTAssertEqual(r.text, "select * from emp;")
        XCTAssertTrue(r.missing.isEmpty)
    }

    func test_resolve_double_ampersand() {
        let r = SubstitutionResolver.resolve("select &&x from dual;", defines: ["X": "1"])
        XCTAssertEqual(r.text, "select 1 from dual;")
        XCTAssertTrue(r.missing.isEmpty)
    }

    func test_resolve_terminator_dot_is_consumed() {
        let r = SubstitutionResolver.resolve("select * from &owner..t;", defines: ["OWNER": "hr"])
        XCTAssertEqual(r.text, "select * from hr.t;")
    }

    func test_resolve_inside_string_literal() {
        let r = SubstitutionResolver.resolve("select 'hi &name' from dual;", defines: ["NAME": "alice"])
        XCTAssertEqual(r.text, "select 'hi alice' from dual;")
    }

    func test_resolve_missing_value_leaves_reference_verbatim() {
        let r = SubstitutionResolver.resolve("select * from &t;", defines: [:])
        XCTAssertEqual(r.text, "select * from &t;")
        XCTAssertEqual(r.missing, ["T"])
    }

    func test_resolve_mixed_resolved_and_missing() {
        let r = SubstitutionResolver.resolve(
            "select &a, &b from dual;",
            defines: ["A": "x"]
        )
        XCTAssertEqual(r.text, "select x, &b from dual;")
        XCTAssertEqual(r.missing, ["B"])
    }

    // MARK: - resolve: case insensitivity

    func test_resolve_is_case_insensitive_in_lookup() {
        let r = SubstitutionResolver.resolve("select &OwNeR from dual;", defines: ["OWNER": "hr"])
        XCTAssertEqual(r.text, "select hr from dual;")
    }

    // MARK: - OffsetMap round-trip

    func test_offset_map_passthrough_round_trip() {
        let original = "select 1 from dual"
        let r = SubstitutionResolver.resolve(original, defines: [:])
        // Pick a range in the resolved text and project back.
        let resolvedRange = 7..<8 // "1"
        let originalRange = r.mapping.originalRange(forResolved: resolvedRange)
        XCTAssertEqual(originalRange, 7..<8)
    }

    func test_offset_map_substitution_growth_projects_to_original() {
        // Original: "select &t from dual"  (positions 7..<9 are `&t`)
        //   t=0..<7: "select "  (passthrough)
        //   t=7..<9: "&t"       (substitution)
        //   t=9..<19: " from dual" (passthrough)
        // Resolved: "select EMPLOYEE from dual" (after "EMPLOYEE" replaces "&t")
        //   r=0..<7: "select "
        //   r=7..<15: "EMPLOYEE"  ← substitution; back-maps to original 7..<9
        //   r=15..<25: " from dual"
        let original = "select &t from dual"
        let r = SubstitutionResolver.resolve(original, defines: ["T": "EMPLOYEE"])
        XCTAssertEqual(r.text, "select EMPLOYEE from dual")

        // Anywhere inside "EMPLOYEE" should map back to the &t reference range.
        let resolvedRange = 10..<13 // a span inside "EMPLOYEE"
        XCTAssertEqual(r.mapping.originalRange(forResolved: resolvedRange), 7..<9)

        // Tail passthrough preserves character offsets relative to original.
        XCTAssertEqual(r.mapping.originalRange(forResolved: 16..<20), 10..<14) // " fro"
    }

    func test_offset_map_terminator_dot_included_in_substitution_range() {
        // Original: "select &owner..t" → resolved: "select hr.t".
        //   `&owner.` (incl. consumed terminator dot) covers original 7..<14.
        //   Literal "." sits at 14..<15; "t" at 15..<16.
        let original = "select &owner..t"
        let r = SubstitutionResolver.resolve(original, defines: ["OWNER": "hr"])
        XCTAssertEqual(r.text, "select hr.t")
        XCTAssertEqual(r.mapping.originalRange(forResolved: 7..<9), 7..<14)
    }

    func test_offset_map_identity_for_empty_input() {
        let r = SubstitutionResolver.resolve("", defines: [:])
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.mapping.originalRange(forResolved: 0..<0), 0..<0)
    }

    // MARK: - && stickiness reported

    func test_scan_reports_sticky_names_for_session_persistence() {
        let scan = SubstitutionResolver.scan("""
            DEFINE owner = hr;
            SELECT * FROM &&owner..emp;
            SELECT * FROM &owner..dept;
            """)
        // Both refs use the same name; the && one makes it sticky.
        XCTAssertEqual(scan.names, ["OWNER"])
        XCTAssertEqual(scan.stickyNames, ["OWNER"])
    }
}
