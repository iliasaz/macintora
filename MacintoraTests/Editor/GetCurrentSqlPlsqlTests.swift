// GetCurrentSqlPlsqlTests.swift
// Integration tests for the PL/SQL anonymous-block path through
// `MainDocumentVM.getCurrentSql`. The detection logic now lives in
// `PlsqlBlockFinder` (tree-sitter walker); these tests treat it as a
// black box so they survive future grammar / walker changes.

import XCTest
@testable import Macintora

@MainActor
final class GetCurrentSqlPlsqlTests: XCTestCase {

    // MARK: - Basic anonymous block

    func test_getCurrentSql_caretInAnonBlock_returnsFullBlock() {
        let sql = "begin\nnull;\nend;\n"
        let doc = MainDocumentVM(text: sql)
        let cursor = sql.range(of: "null")!.lowerBound
        XCTAssertEqual(doc.getCurrentSql(for: cursor..<cursor), "begin\nnull;\nend;")
    }

    func test_getCurrentSql_caretInDeclareBlock_returnsFullBlock() {
        let sql = "declare\n  x number := 1;\nbegin\n  null;\nend;\n"
        let doc = MainDocumentVM(text: sql)
        let cursor = sql.range(of: "null")!.lowerBound
        XCTAssertEqual(doc.getCurrentSql(for: cursor..<cursor),
                       "declare\n  x number := 1;\nbegin\n  null;\nend;")
    }

    func test_getCurrentSql_anonBlockWithTrailingSlash_slashStripped() {
        let sql = "begin\nnull;\nend;\n/\n"
        let doc = MainDocumentVM(text: sql)
        let cursor = sql.range(of: "null")!.lowerBound
        XCTAssertEqual(doc.getCurrentSql(for: cursor..<cursor), "begin\nnull;\nend;")
    }

    // MARK: - Regression: regular SQL still works

    func test_getCurrentSql_regularSQL_notBrokenByPlsqlCheck() {
        let sql = "select 1 from dual;\n"
        let doc = MainDocumentVM(text: sql)
        let cursor = sql.range(of: "from")!.lowerBound
        // Existing behaviour: trailing ; stripped
        XCTAssertEqual(doc.getCurrentSql(for: cursor..<cursor), "select 1 from dual")
    }

    func test_getCurrentSql_twoStatements_caretInSecond_returnsSecond() {
        let sql = "select 1 from dual;\nselect 2 from dual;\n"
        let doc = MainDocumentVM(text: sql)
        let cursor = sql.range(of: "select 2")!.lowerBound
        XCTAssertEqual(doc.getCurrentSql(for: cursor..<cursor), "select 2 from dual")
    }

    // MARK: - Nested block

    func test_getCurrentSql_nestedBlock_caretInInner_returnsOuterBlock() {
        let sql = "begin\n  begin\n    null;\n  end;\nend;\n"
        let doc = MainDocumentVM(text: sql)
        let cursor = sql.range(of: "null")!.lowerBound
        XCTAssertEqual(doc.getCurrentSql(for: cursor..<cursor),
                       "begin\n  begin\n    null;\n  end;\nend;")
    }
}
