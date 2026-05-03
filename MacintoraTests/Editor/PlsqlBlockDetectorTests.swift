// PlsqlBlockDetectorTests.swift
// Tests for PlsqlBlockDetector and the PL/SQL anonymous block path in
// MainDocumentVM.getCurrentSql (issue #14).

import XCTest
@testable import Macintora

// MARK: - PlsqlBlockDetector unit tests

final class PlsqlBlockDetectorTests: XCTestCase {

    // MARK: - Simple BEGIN...END;

    func test_simpleBlock_cursorInside_returnsBlock() {
        let sql = "begin\nnull;\nend;"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, "begin\nnull;\nend;")
    }

    func test_simpleBlock_cursorOnFirstLine_returnsBlock() {
        let sql = "begin\nnull;\nend;"
        let cursor = sql.startIndex  // on 'b' of begin
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, "begin\nnull;\nend;")
    }

    func test_simpleBlock_cursorOnLastLinBeforeEnd_returnsBlock() {
        let sql = "begin\nnull;\nend;"
        let cursor = sql.range(of: "end")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, "begin\nnull;\nend;")
    }

    // MARK: - DECLARE...BEGIN...END;

    func test_declareBlock_cursorInside_returnsFullBlock() {
        let sql = "declare\n  x number;\nbegin\n  null;\nend;"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    func test_declareBlock_cursorOnDeclareLine_returnsFullBlock() {
        let sql = "declare\n  x number;\nbegin\n  null;\nend;"
        let cursor = sql.startIndex
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    func test_declareBlock_cursorOnBeginLine_returnsFullBlock() {
        let sql = "declare\n  x number;\nbegin\n  null;\nend;"
        let cursor = sql.range(of: "begin")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    // MARK: - Trailing `/` terminator

    func test_trailingSlash_isStripped() {
        // The `/` line must NOT be included in the returned SQL.
        let sql = "begin\nnull;\nend;\n/"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        // Range ends after `end;`, before `\n/`
        XCTAssertEqual(result, "begin\nnull;\nend;")
    }

    func test_trailingSlashWithWhitespace_isStripped() {
        let sql = "begin\nnull;\nend;\n /\n"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, "begin\nnull;\nend;")
    }

    func test_noTrailingSlash_returnsBlockAsIs() {
        let sql = "begin\nnull;\nend;\n\nselect 1 from dual;"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, "begin\nnull;\nend;")
    }

    // MARK: - Nested BEGIN...END;

    func test_nestedBlock_cursorInInner_returnsOuterBlock() {
        let sql = "begin\n  begin\n    null;\n  end;\nend;"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    func test_nestedBlock_cursorInOuterBeforeInner_returnsOuterBlock() {
        let sql = "begin\n  dbms_output.put_line('a');\n  begin\n    null;\n  end;\nend;"
        let cursor = sql.range(of: "dbms")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    func test_nestedBlock_cursorInOuterAfterInner_returnsOuterBlock() {
        let sql = "begin\n  begin\n    null;\n  end;\n  dbms_output.put_line('b');\nend;"
        let cursor = sql.range(of: "dbms")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    // MARK: - Cursor on blank line inside block

    func test_blankLineInsideBlock_returnsBlock() {
        let sql = "begin\n\n  null;\n\nend;"
        // Position cursor on the first blank line (after the first '\n')
        let cursor = sql.index(after: sql.startIndex)  // '\n' after 'begin'
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    // MARK: - Cursor NOT inside any block → nil

    func test_regularSQL_returnsNil() {
        let sql = "select 1 from dual"
        let cursor = sql.range(of: "from")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNil(result)
    }

    func test_cursorAfterBlock_returnsNil() {
        let sql = "begin\nnull;\nend;\nselect 1 from dual"
        let cursor = sql.range(of: "select")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNil(result)
    }

    func test_emptyText_returnsNil() {
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: "".startIndex, in: "")
        XCTAssertNil(result)
    }

    // MARK: - Block inside string or comment does not match

    func test_beginInsideString_notRecognized() {
        // 'begin' in a string literal must not be treated as a block keyword.
        let sql = "select 'begin' from dual"
        let cursor = sql.range(of: "select")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNil(result)
    }

    func test_beginInsideLineComment_notRecognized() {
        let sql = "-- begin\nselect 1 from dual"
        let cursor = sql.range(of: "select")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNil(result)
    }

    // MARK: - Multiple blocks in file; cursor in second

    func test_twoBlocks_cursorInSecond_returnsSecondBlock() {
        let sql = "begin\n  null;\nend;\nbegin\n  null;\nend;"
        // The second `null` occurrence
        let firstNull = sql.range(of: "null")!
        let secondNull = sql.range(of: "null", range: firstNull.upperBound..<sql.endIndex)!
        let cursor = secondNull.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, "begin\n  null;\nend;")
    }

    // MARK: - END IF / END LOOP do not close a BEGIN

    func test_ifInsideBlock_notMistakenForBlockEnd() {
        let sql = "begin\n  if true then\n    null;\n  end if;\nend;"
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }

    func test_loopInsideBlock_notMistakenForBlockEnd() {
        let sql = "begin\n  loop\n    exit;\n  end loop;\nend;"
        let cursor = sql.range(of: "exit")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertEqual(result, sql)
    }
}

// MARK: - Integration: getCurrentSql PL/SQL path

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
