//
//  AliasResolverTests.swift
//  MacintoraTests
//
//  Verifies that `AliasResolver` extracts the correct alias-to-table map for
//  the common Oracle relation shapes. Uses the production `parseAndResolve`
//  facade so the test target doesn't need direct tree-sitter linkage.
//

import XCTest
@testable import Macintora

@MainActor
final class AliasResolverTests: XCTestCase {

    // MARK: - Bare table

    func test_bareTable_aliasesUnderTableName() {
        let map = AliasResolver.parseAndResolve("SELECT * FROM employees")
        XCTAssertEqual(map.keys.sorted(), ["EMPLOYEES"])
        XCTAssertEqual(map["EMPLOYEES"]??.name, "EMPLOYEES")
        XCTAssertNil(map["EMPLOYEES"]??.owner)
    }

    // MARK: - Implicit alias

    func test_implicitAlias() {
        let map = AliasResolver.parseAndResolve("SELECT * FROM employees e")
        XCTAssertNotNil(map["E"])
        XCTAssertEqual(map["E"]??.name, "EMPLOYEES")
    }

    // MARK: - AS alias

    func test_asAlias() {
        let map = AliasResolver.parseAndResolve("SELECT * FROM employees AS e")
        XCTAssertNotNil(map["E"])
        XCTAssertEqual(map["E"]??.name, "EMPLOYEES")
    }

    // MARK: - Schema-qualified

    func test_schemaQualified() {
        let map = AliasResolver.parseAndResolve("SELECT * FROM hr.employees e")
        XCTAssertEqual(map["E"]??.name, "EMPLOYEES")
        XCTAssertEqual(map["E"]??.owner, "HR")
    }

    // MARK: - Multiple comma-separated tables

    func test_multipleTablesCommaJoin() {
        let map = AliasResolver.parseAndResolve("SELECT * FROM employees e, departments d")
        XCTAssertEqual(map["E"]??.name, "EMPLOYEES")
        XCTAssertEqual(map["D"]??.name, "DEPARTMENTS")
    }

    // MARK: - Cursor-aware lookup (production path)

    /// Reproduces the bug reported during manual testing: typing
    /// `select b.| from BILLS b` puts the cursor in the SELECT-list, where
    /// `from` is a *sibling* of the enclosing `select` (not an ancestor).
    /// The resolver must still find the FROM-clause aliases by inspecting
    /// each ancestor's named children, not just walking straight up.
    func test_cursorInSelectList_findsAliasesViaSiblingFrom() {
        let source = "SELECT b. FROM BILLS b"
        let cursor = (source as NSString).range(of: "b.").location + 2
        let map = AliasResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(map["B"]??.name, "BILLS",
                       "Cursor inside SELECT must still resolve aliases bound by the sibling FROM")
    }

    func test_cursorInWhereClause_resolvesAlias() {
        let source = "SELECT * FROM BILLS b WHERE b."
        let map = AliasResolver.parseAndResolve(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(map["B"]??.name, "BILLS")
    }

    func test_cursorInGroupBy_resolvesAlias() {
        let source = "SELECT * FROM BILLS b GROUP BY b."
        let map = AliasResolver.parseAndResolve(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(map["B"]??.name, "BILLS",
                       "GROUP BY column reference must still resolve FROM-clause aliases")
    }

    func test_cursorInOrderBy_resolvesAlias() {
        let source = "SELECT * FROM BILLS b ORDER BY b."
        let map = AliasResolver.parseAndResolve(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(map["B"]??.name, "BILLS",
                       "ORDER BY column reference must still resolve FROM-clause aliases")
    }

    /// Reproduces the multi-statement bug: when the buffer holds
    /// `select 42 from dual;\nselect a. from BILLS a`, completion at the
    /// cursor in stmt2 must resolve `a` against stmt2's `from BILLS a`,
    /// not pick up stmt1's `from dual`.
    func test_multiStatement_resolvesAliasFromOwningStatement() {
        let stmt1 = "SELECT 42 FROM dual;\n"
        let stmt2 = "SELECT a. FROM BILLS a"
        let source = stmt1 + stmt2
        let cursor = (source as NSString).range(of: "a. FROM").location + 2
        let map = AliasResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(map["A"]??.name, "BILLS",
                       "`a` belongs to stmt2's FROM, not stmt1's FROM dual")
        XCTAssertNil(map["DUAL"], "stmt1's table must not leak into stmt2's alias map")
    }

    func test_multiStatement_sourceFallback_scopesToCursorStatement() {
        // Identical semantics but force the source-text fallback by feeding
        // a string the parser will fail on (extra noise) — the fallback
        // alone must still scope correctly.
        let source = "SELECT 42 FROM dual; SELECT a. FROM BILLS a;"
        let cursorAfterADot = (source as NSString).range(of: "a. FROM").location + 2
        let map = AliasResolver.aliasesFromSourceText(source, around: cursorAfterADot)
        XCTAssertEqual(map["A"]??.name, "BILLS")
        XCTAssertNil(map["DUAL"])
    }
}
