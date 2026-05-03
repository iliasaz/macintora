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

    // MARK: - Procedure call (signature popup)

    func test_procedureCall_packageMember_emptyArgList() {
        let source = "BEGIN accounts_pkg.debit("
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context,
                       .procedureCall(packageName: "accounts_pkg",
                                      procedureName: "debit",
                                      currentArgumentIndex: 0))
    }

    func test_procedureCall_afterFirstComma_indexAdvances() {
        let source = "BEGIN accounts_pkg.debit(100, "
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context,
                       .procedureCall(packageName: "accounts_pkg",
                                      procedureName: "debit",
                                      currentArgumentIndex: 1))
    }

    func test_procedureCall_skipsNestedParens() {
        // Nested call's args/commas must not perturb the outer index.
        let source = "BEGIN accounts_pkg.debit(get_amount(100, 200), "
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context,
                       .procedureCall(packageName: "accounts_pkg",
                                      procedureName: "debit",
                                      currentArgumentIndex: 1))
    }

    func test_procedureCall_standalone_noPackageQualifier() {
        // Phase 3 lifts this case to surfacing in the popup; the analyzer
        // already classifies it correctly with packageName == nil.
        let source = "BEGIN purge_old("
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        XCTAssertEqual(context,
                       .procedureCall(packageName: nil,
                                      procedureName: "purge_old",
                                      currentArgumentIndex: 0))
    }

    func test_procedureCall_partialArgPrefix_fallsThroughToIdentifier() {
        // Once the user starts typing an argument identifier, the regular
        // completion should take over so they can pick column / variable
        // names rather than the signature row.
        let source = "BEGIN accounts_pkg.debit(am"
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        switch context {
        case .columnReference(_, let prefix), .identifierPrefix(let prefix):
            XCTAssertEqual(prefix, "am")
        default:
            XCTFail("expected identifier-flavoured context, got \(context)")
        }
    }

    func test_procedureCall_dottedArgument_routesToDottedMember() {
        // Inside the call but typing a qualified reference — the dotted
        // member branch wins. Tests that the procedure-call probe doesn't
        // swallow legitimate dotted-member contexts.
        let source = "BEGIN accounts_pkg.debit(emp."
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        if case .dottedMember(let qualifier, let prefix) = context {
            XCTAssertEqual(qualifier, "emp")
            XCTAssertEqual(prefix, "")
        } else {
            XCTFail("expected dottedMember, got \(context)")
        }
    }

    func test_procedureCall_outsideAnyCall_returnsIdentifier() {
        // No enclosing `(` — must not invent one.
        let source = "SELECT "
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        switch context {
        case .columnReference, .identifierPrefix, .afterFromKeyword:
            break
        default:
            XCTFail("expected fallthrough context, got \(context)")
        }
    }

    func test_procedureCall_statementBoundary_abortsWalk() {
        // A `;` between `(` and the cursor means the call isn't really
        // open; the walk should abort rather than reach back into the
        // previous statement.
        let source = "accounts_pkg.debit(100); BEGIN "
        let context = SQLContextAnalyzer.parseAndAnalyze(source, utf16Offset: source.utf16.count)
        switch context {
        case .procedureCall:
            XCTFail("statement boundary must terminate the call walk")
        default:
            break
        }
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
