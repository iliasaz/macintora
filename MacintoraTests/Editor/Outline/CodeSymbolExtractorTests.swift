//
//  CodeSymbolExtractorTests.swift
//  MacintoraTests
//
//  Verifies `CodeSymbolExtractor` pulls the right navigable symbols out of
//  PL/SQL package specs/bodies and standalone subprograms, and that the
//  `CodeOutlineModel` filtering/grouping on top of them behaves. Pure parse —
//  no Oracle connection or network.
//

import XCTest
@testable import Macintora

@MainActor
final class CodeSymbolExtractorTests: XCTestCase {

    // MARK: - Fixtures

    private let packageBody = """
    create or replace package body pkg as

      g_count constant number := 0;
      g_state varchar2(30);

      procedure log(msg varchar2) as
        v_local number;
      begin
        v_local := 1;
        insert into logs(t) values (msg);
      end log;

      procedure refresh as
      begin
        null;
      end refresh;

      function is_ready return boolean as
      begin
        return true;
      end is_ready;

    end pkg;
    """

    private let packageSpec = """
    create or replace package pkg as
      g_max constant number := 100;
      v_name varchar2(30);
      procedure refresh;
      function is_ready return boolean;
    end pkg;
    """

    // MARK: - Helpers

    private func lineOfFirstOccurrence(of needle: String, in source: String) -> Int {
        guard let range = source.range(of: needle) else { return -1 }
        return source[..<range.lowerBound].filter { $0 == "\n" }.count + 1
    }

    // MARK: - Package body

    func test_packageBody_listsMembersInSourceOrder_skippingLocals() {
        let symbols = CodeSymbolExtractor.symbols(in: packageBody)
        XCTAssertEqual(symbols.map(\.name), ["g_count", "g_state", "log", "refresh", "is_ready"])
        XCTAssertEqual(symbols.map(\.kind), [.constant, .variable, .procedure, .procedure, .function])
        XCTAssertFalse(symbols.contains { $0.name == "v_local" }, "locals must not leak into the package outline")
        XCTAssertFalse(symbols.contains { $0.isDeclaration }, "body members are implementations, not declarations")
    }

    func test_packageBody_lineNumbersMatchSource() {
        let symbols = CodeSymbolExtractor.symbols(in: packageBody)
        XCTAssertEqual(symbols.first { $0.name == "g_count" }?.line,
                       lineOfFirstOccurrence(of: "g_count", in: packageBody))
        XCTAssertEqual(symbols.first { $0.name == "log" }?.line,
                       lineOfFirstOccurrence(of: "procedure log", in: packageBody))
        XCTAssertEqual(symbols.first { $0.name == "is_ready" }?.line,
                       lineOfFirstOccurrence(of: "function is_ready", in: packageBody))
        // Source order ⇒ non-decreasing line numbers.
        XCTAssertEqual(symbols.map(\.line), symbols.map(\.line).sorted())
    }

    func test_packageBody_nameRangeRoundTripsToIdentifier() throws {
        let symbols = CodeSymbolExtractor.symbols(in: packageBody)
        let log = try XCTUnwrap(symbols.first { $0.name == "log" })
        let range = try XCTUnwrap(EditorSelectionBridge.range(forUTF16: log.nameRange, in: packageBody))
        XCTAssertEqual(String(packageBody[range]), "log")
        let isReady = try XCTUnwrap(symbols.first { $0.name == "is_ready" })
        let fullRange = try XCTUnwrap(EditorSelectionBridge.range(forUTF16: isReady.fullRange, in: packageBody))
        XCTAssertTrue(packageBody[fullRange].hasPrefix("function is_ready"))
        XCTAssertTrue(packageBody[fullRange].contains("end is_ready"))
    }

    // MARK: - Package spec

    func test_packageSpec_subprogramsAreDeclarations() {
        let symbols = CodeSymbolExtractor.symbols(in: packageSpec)
        XCTAssertEqual(symbols.map(\.name), ["g_max", "v_name", "refresh", "is_ready"])
        XCTAssertEqual(symbols.map(\.kind), [.constant, .variable, .procedure, .function])
        XCTAssertEqual(symbols.first { $0.name == "refresh" }?.isDeclaration, true)
        XCTAssertEqual(symbols.first { $0.name == "is_ready" }?.isDeclaration, true)
        XCTAssertEqual(symbols.first { $0.name == "g_max" }?.isDeclaration, false)
    }

    // MARK: - Real-world-ish body with constructs the grammar can't parse

    func test_packageBody_dropsKeywordNamedNoiseFromMisparsedDeclarations() {
        // TYPE / CURSOR / PRAGMA lines aren't modelled yet; tree-sitter recovers
        // them as `plsql_declaration` nodes whose "name" is the leading keyword.
        // Those must not show up as variables — but the real procedures/vars do.
        let source = """
        create or replace package body pkg as
          type t_rec is record (id number, name varchar2(30));
          cursor c_all is select * from dual;
          e_oops exception;
          pragma exception_init(e_oops, -20001);
          g_count number := 0;

          procedure log(msg varchar2) as
            pragma autonomous_transaction;
          begin
            insert into logs(t) values (msg);
          end log;

          function is_ok return boolean as begin return true; end is_ok;
        end pkg;
        """
        let names = CodeSymbolExtractor.symbols(in: source).map(\.name)
        XCTAssertFalse(names.contains("type"))
        XCTAssertFalse(names.contains("cursor"))
        XCTAssertFalse(names.contains("pragma"))
        XCTAssertTrue(names.contains("g_count"))
        XCTAssertTrue(names.contains("log"))
        XCTAssertTrue(names.contains("is_ok"))
    }

    func test_packageBody_recoversMembers_whenShellFailsToParse() throws {
        // When tree-sitter can't complete the `create_package_body` rule
        // (e.g. PIE_C4_DSL: the body's first few functions use constructs the
        // grammar doesn't fully model — user-defined return types, PIPE ROW,
        // etc. — so the wrapper rule never resolves), the parser falls back
        // to recovery and emits the body's members as siblings of the header
        // tokens under an `ERROR` root. The outline must still find them.
        //
        // Minimal in-grammar repro: a CREATE PACKAGE BODY that's missing the
        // closing `END;` produces the same flattened shape (verified via the
        // PIE_C4_DSL diagnostic test).
        let source = """
        create or replace package body pkg as
          function f return number as begin return 1; end f;
          procedure p as begin null; end p;
        """
        // Sanity: confirm the fixture really does land on the recovery path.
        let root = SQLParserHelper.parse(source).rootNode
        XCTAssertEqual(root?.nodeType, "ERROR",
                       "test fixture must reproduce the ERROR-root recovery shape")

        let symbols = CodeSymbolExtractor.symbols(in: source)
        XCTAssertEqual(symbols.map(\.name), ["f", "p"])
        XCTAssertEqual(symbols.map(\.kind), [.function, .procedure])
    }

    // MARK: - Standalone subprogram

    func test_standaloneFunction_listsItselfAndLocals() {
        let source = """
        create or replace function add_one(p_x number) return number as
          v_acc number := 0;
        begin
          v_acc := p_x + 1;
          return v_acc;
        end add_one;
        """
        let symbols = CodeSymbolExtractor.symbols(in: source)
        XCTAssertEqual(symbols.map(\.name), ["add_one", "v_acc"])
        XCTAssertEqual(symbols.map(\.kind), [.function, .variable])
        XCTAssertEqual(symbols.first { $0.name == "add_one" }?.isDeclaration, false)
    }

    // MARK: - Encoding sanity

    func test_offsets_surviveMultiByteCharactersAhead() throws {
        let source = """
        -- 🚀 launch helper
        create or replace package body p as
          procedure go as begin null; end go;
        end p;
        """
        let symbols = CodeSymbolExtractor.symbols(in: source)
        let goProc = try XCTUnwrap(symbols.first { $0.name == "go" })
        let range = try XCTUnwrap(EditorSelectionBridge.range(forUTF16: goProc.nameRange, in: source))
        XCTAssertEqual(String(source[range]), "go")
        XCTAssertEqual(goProc.line, 3)
    }

    // MARK: - Degenerate input

    func test_emptySource_yieldsNoSymbols() {
        XCTAssertTrue(CodeSymbolExtractor.symbols(in: "").isEmpty)
    }

    func test_garbageSource_yieldsNoSymbolsAndDoesNotCrash() {
        XCTAssertTrue(CodeSymbolExtractor.symbols(in: "this is not valid sql @#$% 12345").isEmpty)
    }

    // MARK: - CodeOutlineModel

    func test_outlineModel_filtersByNameAndKind() {
        let model = CodeOutlineModel()
        model.refresh(from: packageBody)
        XCTAssertFalse(model.hasNoSymbols)

        model.filterText = "log"
        XCTAssertEqual(model.filteredSymbols.map(\.name), ["log"])

        model.filterText = "READY"   // case-insensitive
        XCTAssertEqual(model.filteredSymbols.map(\.name), ["is_ready"])

        model.filterText = ""
        model.kindFilter = .functions
        XCTAssertEqual(model.filteredSymbols.map(\.name), ["is_ready"])

        model.kindFilter = .state
        XCTAssertEqual(Set(model.filteredSymbols.map(\.name)), ["g_count", "g_state"])

        model.kindFilter = .all
        XCTAssertEqual(model.sections.map(\.kind), [.procedure, .function, .variable, .constant])
    }

    func test_outlineModel_availableFilters_dropKindsWithNoSymbols() {
        let model = CodeOutlineModel()
        model.refresh(from: packageBody)   // has procs, funcs, vars + a constant
        XCTAssertEqual(model.availableFilters, [.all, .procedures, .functions, .state])

        model.refresh(from: """
        create or replace package body p as
          procedure a as begin null; end a;
          procedure b as begin null; end b;
        end p;
        """)
        XCTAssertEqual(model.availableFilters, [.all, .procedures])   // no Funcs / Vars chips
    }

    func test_outlineModel_sectionsAreAlphabeticalWithinKind() {
        let model = CodeOutlineModel()
        model.refresh(from: """
        create or replace package body p as
          procedure zeta as begin null; end zeta;
          procedure alpha as begin null; end alpha;
          function gamma return number as begin return 1; end gamma;
          function beta return number as begin return 2; end beta;
        end p;
        """)
        let procedures = model.sections.first { $0.kind == .procedure }?.symbols.map(\.name)
        let functions = model.sections.first { $0.kind == .function }?.symbols.map(\.name)
        XCTAssertEqual(procedures, ["alpha", "zeta"])
        XCTAssertEqual(functions, ["beta", "gamma"])
    }

    func test_outlineModel_currentSymbolFollowsCaret() throws {
        let model = CodeOutlineModel()
        model.refresh(from: packageBody)
        let log = try XCTUnwrap(model.symbols.first { $0.name == "log" })
        // Caret anywhere inside `log`'s body resolves to `log`.
        model.caretUTF16Offset = log.fullRange.lowerBound + 1
        XCTAssertEqual(model.currentSymbolID, log.id)
        // Before the first symbol: nothing current.
        model.caretUTF16Offset = 0
        XCTAssertNil(model.currentSymbolID)
    }
}
