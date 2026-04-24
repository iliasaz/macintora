import XCTest
@testable import Macintora

/// Exercises `MainDocumentVM.getCurrentSql(for:)` — the statement-extraction
/// routine that every toolbar action (Run, Explain, Compile, New Tab, Format)
/// runs over the editor's selection. Previously untested; doubles as a
/// regression harness for the editor migration, since the wrapper must feed
/// the exact same `Range<String.Index>` shape this routine expects.
@MainActor
final class GetCurrentSqlTests: XCTestCase {

    // MARK: - Explicit selection path (non-empty range)

    func test_nonEmptySelection_returnsSelectedTextTrimmed() {
        let sql = "select 1 from dual;\nselect 2 from dual;\n"
        let doc = MainDocumentVM(text: sql)
        let selection = sql.range(of: "select 1 from dual;")!
        XCTAssertEqual(doc.getCurrentSql(for: selection), "select 1 from dual;")
    }

    func test_selectionWithTrailingNewline_isTrimmed() {
        let sql = "select 1 from dual;\n\n"
        let doc = MainDocumentVM(text: sql)
        let selection = sql.range(of: "select 1 from dual;\n")!
        XCTAssertEqual(doc.getCurrentSql(for: selection), "select 1 from dual;")
    }

    // MARK: - Caret path (empty range)

    /// `getCurrentSql` strips the trailing `;` before handing the statement to
    /// oracle-nio (some execution paths choke on it). That's by design — we
    /// codify it here so the behaviour can't silently regress.
    func test_caretInsideSingleStatement_returnsStatementWithoutTrailingSemicolon() {
        let sql = "select 1 from dual;"
        let doc = MainDocumentVM(text: sql)
        let caret = sql.index(sql.startIndex, offsetBy: 3)
        XCTAssertEqual(doc.getCurrentSql(for: caret..<caret), "select 1 from dual")
    }

    func test_caretInSecondStatement_returnsSecondStatement() {
        let sql = "select 1 from dual;\nselect 2 from dual;\n"
        let doc = MainDocumentVM(text: sql)
        // Caret inside "select 2..."
        let caret = sql.range(of: "select 2")!.lowerBound
        let result = doc.getCurrentSql(for: caret..<caret)
        XCTAssertEqual(result, "select 2 from dual")
    }

    func test_caretInEmptyDocument_returnsEmpty() {
        let doc = MainDocumentVM(text: "")
        let result = doc.getCurrentSql(for: "".startIndex..<"".endIndex)
        XCTAssertEqual(result, "")
    }

    // MARK: - Comment & formatting filters

    func test_caretOnStatementWithCommentLine_stripsComment() {
        let sql = """
        -- a comment
        select 1 from dual;
        """
        let doc = MainDocumentVM(text: sql)
        let caret = sql.range(of: "select 1")!.lowerBound
        let result = doc.getCurrentSql(for: caret..<caret)
        XCTAssertEqual(result, "select 1 from dual")
    }

    func test_caretOnBlockTerminator_stripsSlash() {
        // Oracle-style trailing slash on its own line.
        let sql = """
        select 1 from dual;
         /
        """
        let doc = MainDocumentVM(text: sql)
        let caret = sql.range(of: "select")!.lowerBound
        let result = doc.getCurrentSql(for: caret..<caret)
        XCTAssertEqual(result, "select 1 from dual")
    }

    // MARK: - `exec` → `call` rewrite

    func test_caretOnExecLine_rewrittenAsCall() {
        let sql = "exec pkg.do_thing();\n"
        let doc = MainDocumentVM(text: sql)
        let caret = sql.range(of: "pkg")!.lowerBound
        let result = doc.getCurrentSql(for: caret..<caret)
        XCTAssertEqual(result, "call pkg.do_thing()")
    }
}
