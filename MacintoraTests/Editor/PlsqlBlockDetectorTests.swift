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

    // MARK: - DECLARE block followed by SQL statement (issue from PR #19 follow-up)

    func test_declareBlock_followedBySelect_cursorInBlock_returnsBlockOnly() {
        let sql = """
        declare
        a number := 0;
        begin
        dbms_output.put_line('test');
        end;
        /

        select * from dual;
        """
        let cursor = sql.range(of: "dbms_output")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("declare") ?? false)
        XCTAssertTrue(result?.hasSuffix("end;") ?? false)
        XCTAssertFalse(result?.contains("/") ?? true)
        XCTAssertFalse(result?.contains("select") ?? true)
    }

    func test_declareBlock_followedBySelect_cursorOnSelect_returnsNil() {
        let sql = """
        declare
        a number := 0;
        begin
        dbms_output.put_line('test');
        end;
        /

        select * from dual;
        """
        let cursor = sql.range(of: "select")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNil(result)
    }

    // MARK: - Multiple top-level blocks separated by `/`

    /// Real-world repro from `plsql-test.macintora`: a SELECT, a plain
    /// BEGIN/END, a DECLARE block, another plain BEGIN/END, and a final
    /// SELECT — all separated by `/`. Cursor inside the second plain block
    /// must NOT pull in the earlier DECLARE; that would yield the previous
    /// DECLARE's text plus the intervening `/` as the "block" — invalid
    /// PL/SQL that the server rejects.
    func test_multipleTopLevelBlocks_cursorInBlockAfterDeclare_returnsOnlyThatBlock() {
        let sql = """
        select * from dual;

        begin
        dbms_output.put_line('test');
        end;
        /

        declare
        a number := 0;
        begin
        dbms_output.put_line('test');
        end;
        /

        begin
        dbms_output.put_line('test2');
        end;
        /

        select * from dual;
        """
        // Cursor on the SECOND plain begin/end (after the DECLARE block).
        let cursor = sql.range(of: "test2")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("begin") ?? false, "expected plain begin/end, got: \(result ?? "nil")")
        XCTAssertTrue(result?.hasSuffix("end;") ?? false)
        XCTAssertFalse(result?.contains("declare") ?? true, "must not pull in the earlier DECLARE")
        XCTAssertFalse(result?.contains("/") ?? true)
        XCTAssertEqual(result?.components(separatedBy: "begin").count, 2, "expected exactly one begin")
    }

    func test_multipleTopLevelBlocks_cursorInPlainBeforeDeclare_returnsOnlyThatBlock() {
        let sql = """
        select * from dual;

        begin
        dbms_output.put_line('plain1');
        end;
        /

        declare
        a number := 0;
        begin
        dbms_output.put_line('decl');
        end;
        /
        """
        let cursor = sql.range(of: "plain1")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("begin") ?? false)
        XCTAssertFalse(result?.contains("declare") ?? true)
    }

    func test_multipleTopLevelBlocks_cursorInDeclareBlock_returnsCorrectBlock() {
        let sql = """
        begin
        null;
        end;
        /

        declare
        x number;
        begin
        null;
        end;
        /

        begin
        null;
        end;
        """
        let cursor = sql.range(of: "x number")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("declare") ?? false)
        XCTAssertTrue(result?.hasSuffix("end;") ?? false)
        // Should be just one DECLARE..END;, not pulling in adjacent plain blocks
        XCTAssertEqual(result?.components(separatedBy: "begin").count, 2)
        XCTAssertEqual(result?.components(separatedBy: "end;").count, 2)
    }

    // MARK: - Nested: DECLARE with inner PROCEDURE

    func test_declare_with_inner_procedure_cursorInOuterBody_returnsOuterBlock() {
        let sql = """
        declare
          procedure p is
          begin
            null;
          end;
        begin
          p;
        end;
        """
        let cursor = sql.range(of: "p;\n")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("declare") ?? false)
        XCTAssertTrue(result?.hasSuffix("end;") ?? false)
    }

    func test_declare_with_inner_procedure_cursorInProcedureBody_returnsOuterBlock() {
        let sql = """
        declare
          procedure p is
          begin
            null;
          end;
        begin
          p;
        end;
        """
        let cursor = sql.range(of: "null")!.lowerBound
        let result = PlsqlBlockDetector.plsqlAnonBlockSQL(at: cursor, in: sql)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("declare") ?? false)
        XCTAssertTrue(result?.hasSuffix("end;") ?? false)
        // The outer block contains both the inner `end;` and the outer `end;`.
        let endCount = result?.components(separatedBy: "end;").count ?? 0
        XCTAssertEqual(endCount, 3)
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
