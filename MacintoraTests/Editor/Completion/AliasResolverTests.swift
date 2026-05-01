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
}
