//
//  ScriptLexerTests.swift
//  MacintoraTests
//

import XCTest
@testable import Macintora

final class ScriptLexerTests: XCTestCase {

    // MARK: - Helpers

    private func texts(_ source: String) -> [String] {
        ScriptLexer.split(source).units.map { $0.text }
    }

    private func kinds(_ source: String) -> [CommandUnit.Kind] {
        ScriptLexer.split(source).units.map { $0.kind }
    }

    // MARK: - Plain SQL

    func test_singleStatement_strips_trailing_semicolon() {
        XCTAssertEqual(texts("select 1 from dual;"), ["select 1 from dual"])
    }

    func test_singleStatement_no_terminator() {
        XCTAssertEqual(texts("select 1 from dual"), ["select 1 from dual"])
    }

    func test_two_statements_split_on_semicolon() {
        XCTAssertEqual(
            texts("select 1 from dual;\nselect 2 from dual;\n"),
            ["select 1 from dual", "select 2 from dual"]
        )
    }

    func test_two_statements_one_line() {
        XCTAssertEqual(
            texts("select 1 from dual; select 2 from dual;"),
            ["select 1 from dual", "select 2 from dual"]
        )
    }

    func test_division_is_not_a_split() {
        XCTAssertEqual(texts("select a/b from dual;"), ["select a/b from dual"])
    }

    // MARK: - Comments

    func test_line_comment_between_statements_is_skipped() {
        let src = """
        -- the answer
        select 42 from dual;
        """
        XCTAssertEqual(texts(src), ["select 42 from dual"])
    }

    func test_block_comment_between_statements_is_skipped() {
        let src = """
        /* the answer */
        select 42 from dual;
        """
        XCTAssertEqual(texts(src), ["select 42 from dual"])
    }

    func test_line_comment_inside_string_is_not_a_comment() {
        let src = "select '-- not a comment' from dual;"
        XCTAssertEqual(texts(src), ["select '-- not a comment' from dual"])
    }

    func test_block_comment_inside_string_is_not_a_comment() {
        let src = "select '/* not a comment */' from dual;"
        XCTAssertEqual(texts(src), ["select '/* not a comment */' from dual"])
    }

    func test_inline_block_comment_inside_statement_is_preserved() {
        let src = "select /* hi */ 1 from dual;"
        XCTAssertEqual(texts(src), ["select /* hi */ 1 from dual"])
    }

    // MARK: - String literals & q-quotes

    func test_single_quote_escape_keeps_string_intact() {
        let src = "select 'it''s ok; really' from dual; select 2 from dual;"
        XCTAssertEqual(
            texts(src),
            ["select 'it''s ok; really' from dual", "select 2 from dual"]
        )
    }

    func test_qquote_with_brackets_does_not_split() {
        let src = "select q'[hello; world]' from dual; select 2 from dual;"
        XCTAssertEqual(
            texts(src),
            ["select q'[hello; world]' from dual", "select 2 from dual"]
        )
    }

    func test_qquote_with_parens() {
        let src = "select q'(a; b)' from dual;"
        XCTAssertEqual(texts(src), ["select q'(a; b)' from dual"])
    }

    func test_qquote_with_braces() {
        let src = "select q'{a; b}' from dual;"
        XCTAssertEqual(texts(src), ["select q'{a; b}' from dual"])
    }

    func test_qquote_with_angles() {
        let src = "select q'<a; b>' from dual;"
        XCTAssertEqual(texts(src), ["select q'<a; b>' from dual"])
    }

    func test_qquote_with_bang_delimiter() {
        let src = "select q'!a; b!' from dual;"
        XCTAssertEqual(texts(src), ["select q'!a; b!' from dual"])
    }

    func test_qquote_uppercase_Q() {
        let src = "select Q'[a; b]' from dual;"
        XCTAssertEqual(texts(src), ["select Q'[a; b]' from dual"])
    }

    func test_qquote_with_n_prefix() {
        let src = "select Nq'[a; b]' from dual;"
        XCTAssertEqual(texts(src), ["select Nq'[a; b]' from dual"])
    }

    func test_quoted_identifier_does_not_split() {
        let src = "select \"weird;name\" from dual;"
        XCTAssertEqual(texts(src), ["select \"weird;name\" from dual"])
    }

    // MARK: - PL/SQL blocks

    func test_anonymous_begin_end_block_terminated_by_slash() {
        let src = """
        BEGIN
          NULL;
        END;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
        XCTAssertEqual(units[0].text, "BEGIN\n  NULL;\nEND;")
    }

    func test_declare_block_terminated_by_slash() {
        let src = """
        DECLARE x NUMBER;
        BEGIN
          x := 1;
        END;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
    }

    func test_create_or_replace_function_terminated_by_slash() {
        let src = """
        CREATE OR REPLACE FUNCTION f RETURN NUMBER IS
        BEGIN
          RETURN 1;
        END;
        /
        SELECT f FROM dual;
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
        XCTAssertEqual(units[1].kind, .sql)
        XCTAssertEqual(units[1].text, "SELECT f FROM dual")
    }

    func test_create_procedure_terminated_by_slash() {
        let src = """
        CREATE PROCEDURE p IS BEGIN NULL; END;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
    }

    func test_create_package_body_is_plsql() {
        let src = """
        CREATE PACKAGE BODY pkg IS
          PROCEDURE q IS BEGIN NULL; END;
        END pkg;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
    }

    func test_editionable_create_function_is_plsql() {
        let src = """
        CREATE OR REPLACE EDITIONABLE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
    }

    func test_create_type_without_body_is_sql() {
        let src = "CREATE TYPE addr_t AS OBJECT (street VARCHAR2(60));"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .sql)
    }

    func test_create_type_body_is_plsql() {
        let src = """
        CREATE TYPE BODY addr_t AS
          MEMBER FUNCTION pretty RETURN VARCHAR2 IS BEGIN RETURN street; END;
        END;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .plsqlBlock)
    }

    func test_create_table_is_sql_not_plsql() {
        let src = "CREATE TABLE t (id NUMBER); INSERT INTO t VALUES (1);"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].kind, .sql)
        XCTAssertEqual(units[0].text, "CREATE TABLE t (id NUMBER)")
        XCTAssertEqual(units[1].kind, .sql)
        XCTAssertEqual(units[1].text, "INSERT INTO t VALUES (1)")
    }

    // MARK: - `;` followed by trailing `/` line

    func test_semicolon_followed_by_slash_line_absorbs_slash() {
        let src = """
        SELECT 1 FROM dual;
        /
        SELECT 2 FROM dual;
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].text, "SELECT 1 FROM dual")
        XCTAssertEqual(units[1].text, "SELECT 2 FROM dual")
    }

    // MARK: - SQL*Plus directives

    func test_at_include_recognized_at_line_start() {
        let src = "@helper.sql\nSELECT 1 FROM dual;"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        if case .sqlplus(.include(let path, let dbl)) = units[0].kind {
            XCTAssertEqual(path, "helper.sql")
            XCTAssertFalse(dbl)
        } else {
            XCTFail("expected include directive, got \(units[0].kind)")
        }
        XCTAssertEqual(units[1].kind, .sql)
    }

    func test_double_at_include_recognized() {
        let src = "@@subdir/helper.sql\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        if case .sqlplus(.include(let path, let dbl)) = units[0].kind {
            XCTAssertEqual(path, "subdir/helper.sql")
            XCTAssertTrue(dbl)
        } else {
            XCTFail("expected include directive")
        }
    }

    func test_at_in_dblink_is_not_a_directive() {
        let src = "select * from t@dblink;"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .sql)
        XCTAssertEqual(units[0].text, "select * from t@dblink")
    }

    func test_set_serveroutput_on() {
        let src = "SET SERVEROUTPUT ON\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].kind, .sqlplus(.set(.serverOutput(true))))
    }

    func test_set_echo_off() {
        let src = "set echo off\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.set(.echo(false))))
    }

    func test_set_feedback_rows() {
        let src = "SET FEEDBACK 5\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.set(.feedback(.rows(5)))))
    }

    func test_set_define_off() {
        let src = "SET DEFINE OFF\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.set(.define(.off))))
    }

    func test_set_define_prefix() {
        let src = "SET DEFINE #\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.set(.define(.prefix("#")))))
    }

    func test_define_with_value() {
        let src = "DEFINE owner = hr\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.define(name: "OWNER", value: "hr")))
    }

    func test_define_with_quoted_value() {
        let src = "DEFINE owner = 'hr schema'\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.define(name: "OWNER", value: "hr schema")))
    }

    func test_undefine() {
        let src = "UNDEFINE owner\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.undefine(name: "owner")))
    }

    func test_prompt_message() {
        let src = "PROMPT Hello, world\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.prompt(message: "Hello, world")))
    }

    func test_remark_is_directive() {
        let src = "REM this is a sql*plus comment\nSELECT 1 FROM dual;"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].kind, .sqlplus(.remark(text: "this is a sql*plus comment")))
        XCTAssertEqual(units[1].kind, .sql)
    }

    func test_remark_long_form() {
        let src = "REMARK hi\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.remark(text: "hi")))
    }

    func test_show_errors() {
        let src = "SHOW ERRORS\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.showErrors))
    }

    func test_whenever_sqlerror_exit_failure() {
        let src = "WHENEVER SQLERROR EXIT FAILURE\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.whenever(.sqlError, .exit(.failure, commitOrRollback: nil))))
    }

    func test_whenever_sqlerror_exit_failure_rollback() {
        let src = "WHENEVER SQLERROR EXIT FAILURE ROLLBACK\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.whenever(.sqlError, .exit(.failure, commitOrRollback: .rollback))))
    }

    func test_whenever_sqlerror_continue_none() {
        let src = "WHENEVER SQLERROR CONTINUE NONE\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.whenever(.sqlError, .continue(.noAction))))
    }

    func test_whenever_sqlerror_continue_bare() {
        let src = "WHENEVER SQLERROR CONTINUE\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units[0].kind, .sqlplus(.whenever(.sqlError, .continue(.noAction))))
    }

    // MARK: - Mixed scripts

    func test_mixed_directives_and_statements() {
        let src = """
        SET SERVEROUTPUT ON
        DEFINE owner = hr
        SELECT * FROM dual;
        BEGIN
          DBMS_OUTPUT.PUT_LINE('hi');
        END;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 4)
        XCTAssertEqual(units[0].kind, .sqlplus(.set(.serverOutput(true))))
        XCTAssertEqual(units[1].kind, .sqlplus(.define(name: "OWNER", value: "hr")))
        XCTAssertEqual(units[2].kind, .sql)
        XCTAssertEqual(units[2].text, "SELECT * FROM dual")
        XCTAssertEqual(units[3].kind, .plsqlBlock)
    }

    func test_lone_slash_between_units_is_discarded() {
        let src = """
        SELECT 1 FROM dual;
        /
        SELECT 2 FROM dual;
        /
        """
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].text, "SELECT 1 FROM dual")
        XCTAssertEqual(units[1].text, "SELECT 2 FROM dual")
    }

    // MARK: - Original-range fidelity

    func test_original_range_covers_full_text_including_terminator() {
        let src = "select 1 from dual;\nselect 2 from dual;\n"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 2)
        // First unit's range covers the leading "select 1 from dual;" (without the \n)
        let r0 = units[0].originalRange
        XCTAssertEqual(String(src[r0]), "select 1 from dual;")
        let r1 = units[1].originalRange
        XCTAssertEqual(String(src[r1]), "select 2 from dual;")
    }

    func test_empty_input_yields_no_units() {
        XCTAssertTrue(ScriptLexer.split("").units.isEmpty)
        XCTAssertTrue(ScriptLexer.split("   \n\n  \n").units.isEmpty)
        XCTAssertTrue(ScriptLexer.split("-- only comment\n").units.isEmpty)
    }

    // MARK: - Bind-variable text passes through

    func test_bind_variables_remain_in_text() {
        let src = "select * from emp where id = :id and dept = :dept;"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].text, "select * from emp where id = :id and dept = :dept")
    }

    // MARK: - Substitution variables remain in text (Phase 1 will resolve)

    func test_substitution_variable_remains_in_text() {
        let src = "select * from &owner..t where id = &&id;"
        let units = ScriptLexer.split(src).units
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].text, "select * from &owner..t where id = &&id")
    }
}
