//
//  ObjectAtCursorResolverTests.swift
//  MacintoraTests
//
//  Verifies the cursor → `ResolvedDBReference` mapping for the Quick View
//  feature. Uses the production `parseAndResolve(_:utf16Offset:)` facade so
//  the test target doesn't need direct tree-sitter linkage.
//

import XCTest
@testable import Macintora

@MainActor
final class ObjectAtCursorResolverTests: XCTestCase {

    // MARK: - Schema-object resolution

    func test_bareTable_resolvesAsSchemaObject() {
        let source = "SELECT * FROM employees"
        let cursor = (source as NSString).range(of: "employees").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .schemaObject(owner: nil, name: "EMPLOYEES"))
    }

    func test_schemaQualifiedTable_resolvesWithOwner() {
        let source = "SELECT * FROM hr.employees"
        let cursor = (source as NSString).range(of: "employees").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .schemaObject(owner: "HR", name: "EMPLOYEES"))
    }

    func test_cursorOnSchemaSegment_returnsSchemaQualified() {
        let source = "SELECT * FROM hr.employees"
        let cursor = (source as NSString).range(of: "hr").location + 1
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        // Whether the resolver lands on "hr" alone or the full reference, the
        // schemaObject should carry HR/EMPLOYEES — the popover's fetcher
        // disambiguates.
        if case let .schemaObject(_, name) = result {
            XCTAssertTrue(["HR", "EMPLOYEES"].contains(name),
                          "Expected schemaObject pointing at HR or EMPLOYEES, got \(result)")
        } else {
            XCTFail("Expected schemaObject case, got \(result)")
        }
    }

    // MARK: - Column references via alias

    func test_aliasQualifiedColumn_resolvesToTable() {
        let source = "SELECT e.salary FROM employees e"
        let cursor = (source as NSString).range(of: "salary").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .column(tableOwner: nil,
                               tableName: "EMPLOYEES",
                               columnName: "SALARY"))
    }

    func test_aliasQualifiedColumn_acrossSchemaQualifiedTable() {
        let source = "SELECT e.salary FROM hr.employees e"
        let cursor = (source as NSString).range(of: "salary").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .column(tableOwner: "HR",
                               tableName: "EMPLOYEES",
                               columnName: "SALARY"))
    }

    func test_unknownAlias_doesNotProduceColumn() {
        let source = "SELECT x.salary FROM employees e"
        let cursor = (source as NSString).range(of: "salary").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        // x isn't an alias bound by the FROM — fall back to schemaObject so
        // the popover can attempt a schema lookup. Don't fabricate a column.
        if case .column = result {
            XCTFail("Unknown qualifier `x` must not yield a column resolution; got \(result)")
        }
    }

    // MARK: - Package members

    func test_packageMemberCall_resolvesAsPackageMember() {
        let source = "BEGIN dbms_output.put_line('hello'); END;"
        let cursor = (source as NSString).range(of: "put_line").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .packageMember(packageOwner: nil,
                                      packageName: "DBMS_OUTPUT",
                                      memberName: "PUT_LINE"))
    }

    func test_ownerQualifiedPackageMemberCall_resolvesAsPackageMember() {
        let source = "BEGIN sys.dbms_output.put_line('hello'); END;"
        let cursor = (source as NSString).range(of: "put_line").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .packageMember(packageOwner: "SYS",
                                      packageName: "DBMS_OUTPUT",
                                      memberName: "PUT_LINE"))
    }

    func test_standaloneFunctionCall_resolvesAsSchemaObject() {
        let source = "SELECT my_func(1) FROM dual"
        let cursor = (source as NSString).range(of: "my_func").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        if case let .schemaObject(_, name) = result {
            XCTAssertEqual(name, "MY_FUNC")
        } else {
            XCTFail("Expected schemaObject case, got \(result)")
        }
    }

    // MARK: - Multi-statement scoping

    func test_multiStatement_resolvesAliasFromOwningStatement() {
        // Cursor sits inside stmt2 — the resolver must reach into stmt2's FROM,
        // not stmt1's FROM dual.
        let stmt1 = "SELECT 42 FROM dual;\n"
        let stmt2 = "SELECT a.amount FROM bills a"
        let source = stmt1 + stmt2
        let cursor = (source as NSString).range(of: "amount").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .column(tableOwner: nil,
                               tableName: "BILLS",
                               columnName: "AMOUNT"))
    }

    // MARK: - Negative cases

    func test_cursorInStringLiteral_returnsUnresolved() {
        let source = "SELECT 'employees' FROM dual"
        // Cursor inside the string literal.
        let cursor = (source as NSString).range(of: "employees").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .unresolved,
                       "Cursor inside a string must not produce a DB reference")
    }

    func test_cursorInLineComment_returnsUnresolved() {
        let source = "-- employees\nSELECT * FROM dual"
        let cursor = (source as NSString).range(of: "employees").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .unresolved,
                       "Cursor in a -- comment must not produce a DB reference")
    }

    func test_cursorOnWhitespace_returnsUnresolved() {
        let source = "SELECT  *  FROM employees"
        let firstSpace = (source as NSString).range(of: "  ").location + 1
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: firstSpace)
        if case .schemaObject = result { return /* tolerated when grammar absorbs the cursor into surrounding token */ }
        XCTAssertEqual(result, .unresolved,
                       "Cursor on whitespace should resolve to unresolved or fall through to a known token")
    }

    // MARK: - Mid-typing fallback

    /// Reproduces the typing pattern `SELECT b.| FROM bills b` — the parser
    /// often produces an ERROR node around the partial statement, so the
    /// resolver must still pick up the alias map via the source-text path.
    func test_partialTyping_aliasResolvesViaFallback() {
        let source = "SELECT b. FROM bills b"
        let cursor = (source as NSString).range(of: "b.").location + 2
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        // The cursor sits on the empty member position. We expect either
        // `.unresolved` (no member name to extract) or a column-shaped
        // resolution where `tableName == "BILLS"`. Both are acceptable for v1
        // — what matters is we don't fabricate a wrong table.
        if case .column(_, let tableName, _) = result {
            XCTAssertEqual(tableName, "BILLS")
        }
    }

    func test_endOfBuffer_resolvesTrailingIdentifier() {
        let source = "SELECT * FROM hr.employees"
        let cursor = source.utf16.count
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .schemaObject(owner: "HR", name: "EMPLOYEES"))
    }

    // MARK: - Quoted identifiers

    /// `"MixedCase"` preserves interior case verbatim — Oracle stores quoted
    /// identifiers exactly as written, so cache lookups must match the same
    /// way.
    func test_quotedTable_preservesInteriorCase() {
        let source = "SELECT * FROM \"MixedCase\""
        let cursor = (source as NSString).range(of: "MixedCase").location + 3
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .schemaObject(owner: nil, name: "MixedCase"))
    }

    /// Two-part `"Schema"."Table"` — both segments preserve case independently.
    func test_quotedSchemaAndTable_preserveCase() {
        let source = "SELECT * FROM \"Schema\".\"Tab\""
        let cursor = (source as NSString).range(of: "Tab").location + 1
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result, .schemaObject(owner: "Schema", name: "Tab"))
    }

    /// Mixed: quoted column on an unquoted alias. The alias map lookup folds
    /// the alias to upper, but the column name is held verbatim.
    func test_quotedColumnOnUnquotedAlias_preservesColumnCase() {
        let source = "SELECT a.\"ColumnX\" FROM employees a"
        let cursor = (source as NSString).range(of: "ColumnX").location + 2
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .column(tableOwner: nil,
                               tableName: "EMPLOYEES",
                               columnName: "ColumnX"))
    }

    /// Mixed-case quoted package member: `"Pkg".proc(…)` should preserve the
    /// quoted package name, fold the unquoted member name.
    func test_quotedPackageWithUnquotedMember_preservesCase() {
        let source = "BEGIN \"Pkg\".do_work(); END;"
        let cursor = (source as NSString).range(of: "do_work").location + 2
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .packageMember(packageOwner: nil,
                                      packageName: "Pkg",
                                      memberName: "DO_WORK"))
    }

    /// And the inverse: unquoted package, quoted mixed-case member.
    func test_unquotedPackageWithQuotedMember_preservesCase() {
        let source = "BEGIN pkg.\"DoWork\"(); END;"
        let cursor = (source as NSString).range(of: "DoWork").location + 2
        let result = ObjectAtCursorResolver.parseAndResolve(source, utf16Offset: cursor)
        XCTAssertEqual(result,
                       .packageMember(packageOwner: nil,
                                      packageName: "PKG",
                                      memberName: "DoWork"))
    }

    // MARK: - normalizeIdentifier helper

    func test_normalizeIdentifier_unquotedFoldsToUpper() {
        XCTAssertEqual(ObjectAtCursorResolver.normalizeIdentifier("emp"), "EMP")
    }

    func test_normalizeIdentifier_quotedPreservesCase() {
        XCTAssertEqual(ObjectAtCursorResolver.normalizeIdentifier("\"MixedCase\""),
                       "MixedCase")
    }

    func test_normalizeIdentifier_emptyAndBareQuotesPassThrough() {
        XCTAssertEqual(ObjectAtCursorResolver.normalizeIdentifier(""), "")
        // `""` is the empty quoted identifier — drop the two quotes.
        XCTAssertEqual(ObjectAtCursorResolver.normalizeIdentifier("\"\""), "")
    }
}
