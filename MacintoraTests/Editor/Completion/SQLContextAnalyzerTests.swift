//
//  SQLContextAnalyzerTests.swift
//  MacintoraTests
//
//  Verifies that `SQLContextAnalyzer` returns the right `CompletionContext`
//  for a representative slice of partial SQL inputs. Uses the production
//  `parseAndAnalyze` facade so the test target doesn't have to link the
//  plugin's tree-sitter products directly.
//

import XCTest
@testable import Macintora

@MainActor
final class SQLContextAnalyzerTests: XCTestCase {

    // MARK: - FROM clause

    func test_afterFromKeyword_emptyPrefix() {
        let source = "SELECT * FROM "
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context, .afterFromKeyword(prefix: ""))
    }

    func test_afterFromKeyword_partialIdentifier() {
        let source = "SELECT * FROM emp"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context, .afterFromKeyword(prefix: "emp"))
    }

    // MARK: - WHERE clause column

    func test_whereClause_columnReference() {
        let source = "SELECT * FROM employees WHERE sa"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        if case .columnReference(let qualifier, let prefix) = context {
            XCTAssertNil(qualifier)
            XCTAssertEqual(prefix, "sa")
        } else {
            XCTFail("expected columnReference, got \(context)")
        }
    }

    // MARK: - Dotted member (alias.col, schema.obj)

    func test_dottedMember_aliasDotColumn() {
        let source = "SELECT e. FROM employees e"
        // Cursor sits right after "e."
        let cursor = (source as NSString).range(of: "e.").location + 2
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: cursor)
        if case .dottedMember(let qualifier, let prefix) = context {
            XCTAssertEqual(qualifier, "e")
            XCTAssertEqual(prefix, "")
        } else {
            XCTFail("expected dottedMember, got \(context)")
        }
    }

    func test_dottedMember_schemaDotPartialName() {
        let source = "SELECT * FROM hr.emp"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        if case .dottedMember(let qualifier, let prefix) = context {
            XCTAssertEqual(qualifier, "hr")
            XCTAssertEqual(prefix, "emp")
        } else {
            XCTFail("expected dottedMember, got \(context)")
        }
    }

    // MARK: - String / comment suppression

    func test_insideStringLiteral_returnsNone() {
        let source = "SELECT 'hello wo"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context, .none)
    }

    func test_insideLineComment_returnsNone() {
        let source = "-- pick a tab\nSELECT * FROM dual"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: 13)
        XCTAssertEqual(context, .none)
    }

    // MARK: - ERROR-node fallback (mid-typing tolerance)

    func test_brokenSyntax_stillReturnsContext() {
        // Missing comma; the tree may have ERROR nodes but the backward scan
        // should still extract the prefix.
        let source = "SELECT col1 col2 FROM tab WHERE c"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        switch context {
        case .columnReference(_, let prefix), .identifierPrefix(let prefix):
            XCTAssertEqual(prefix, "c")
        default:
            XCTFail("expected columnReference or identifierPrefix, got \(context)")
        }
    }
}
