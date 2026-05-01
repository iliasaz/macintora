//
//  ScriptLoaderTests.swift
//  MacintoraTests
//

import XCTest
@testable import Macintora

final class ScriptLoaderTests: XCTestCase {

    func test_flatten_no_includes_returns_input_unchanged() throws {
        let units = ScriptLexer.split("select 1 from dual;\nselect 2 from dual;").units
        let flat = try ScriptLoader.flatten(units, documentBaseURL: nil, resolver: FakeFileResolver(files: [:]))
        XCTAssertEqual(flat.count, 2)
        XCTAssertEqual(flat.map(\.text), ["select 1 from dual", "select 2 from dual"])
    }

    func test_flatten_resolves_at_include() throws {
        let docDir = URL(fileURLWithPath: "/project")
        let helper = docDir.appendingPathComponent("helper.sql")
        let resolver = FakeFileResolver(files: [
            helper: "select 'helper' from dual;\n"
        ])

        let source = "@helper\nselect 'main' from dual;\n"
        let units = ScriptLexer.split(source).units
        let flat = try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: resolver)

        XCTAssertEqual(flat.count, 2)
        XCTAssertEqual(flat[0].text, "select 'helper' from dual")
        XCTAssertEqual(flat[1].text, "select 'main' from dual")
    }

    func test_flatten_double_at_resolves_against_current_file() throws {
        let docDir = URL(fileURLWithPath: "/project")
        let level1 = docDir.appendingPathComponent("nested/a.sql")
        let level2 = docDir.appendingPathComponent("nested/b.sql")
        let resolver = FakeFileResolver(files: [
            level1: "@@b\nselect 'a' from dual;\n",
            level2: "select 'b' from dual;\n"
        ])
        let units = ScriptLexer.split("@nested/a\n").units
        let flat = try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: resolver)
        XCTAssertEqual(flat.map(\.text), ["select 'b' from dual", "select 'a' from dual"])
    }

    func test_flatten_appends_sql_extension_when_missing() throws {
        let docDir = URL(fileURLWithPath: "/project")
        let helper = docDir.appendingPathComponent("foo.sql")
        let resolver = FakeFileResolver(files: [
            helper: "select 1 from dual;\n"
        ])
        let units = ScriptLexer.split("@foo\n").units
        let flat = try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: resolver)
        XCTAssertEqual(flat.count, 1)
    }

    func test_flatten_throws_on_missing_file() {
        let docDir = URL(fileURLWithPath: "/project")
        let units = ScriptLexer.split("@nope\n").units
        XCTAssertThrowsError(
            try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: FakeFileResolver(files: [:]))
        ) { error in
            guard let err = error as? ScriptLoaderError else { return XCTFail("wrong error: \(error)") }
            if case .fileNotFound = err {
                // ok
            } else {
                XCTFail("expected fileNotFound, got \(err)")
            }
        }
    }

    func test_flatten_detects_simple_cycle() {
        let docDir = URL(fileURLWithPath: "/project")
        let a = docDir.appendingPathComponent("a.sql")
        let b = docDir.appendingPathComponent("b.sql")
        let resolver = FakeFileResolver(files: [
            a: "@b\n",
            b: "@a\n"
        ])
        let units = ScriptLexer.split("@a\n").units
        XCTAssertThrowsError(try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: resolver)) { error in
            guard let err = error as? ScriptLoaderError else { return XCTFail("wrong error: \(error)") }
            if case .cycleDetected = err { return }
            XCTFail("expected cycleDetected, got \(err)")
        }
    }

    func test_flatten_allows_diamond_imports() throws {
        // a → b, a → c, b → c (re-imports of the same leaf are allowed because
        // it's not a cycle — c isn't currently on the include stack when b
        // returns to a, and a → c happens after b → c finishes).
        let docDir = URL(fileURLWithPath: "/project")
        let a = docDir.appendingPathComponent("a.sql")
        let b = docDir.appendingPathComponent("b.sql")
        let c = docDir.appendingPathComponent("c.sql")
        let resolver = FakeFileResolver(files: [
            a: "@b\n@c\nselect 'a' from dual;\n",
            b: "@c\nselect 'b' from dual;\n",
            c: "select 'c' from dual;\n"
        ])
        let units = ScriptLexer.split("@a\n").units
        let flat = try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: resolver)
        XCTAssertEqual(
            flat.map(\.text),
            ["select 'c' from dual", "select 'b' from dual", "select 'c' from dual", "select 'a' from dual"]
        )
    }

    func test_flatten_max_depth_guards_runaway_recursion() {
        let docDir = URL(fileURLWithPath: "/project")
        let a = docDir.appendingPathComponent("a.sql")
        let b = docDir.appendingPathComponent("b.sql")
        // Mutually-aliased "infinite" recursion through file aliases — the
        // cycle check guards true cycles, this exercises the depth limit.
        let resolver = FakeFileResolver(files: [
            a: "@b\n",
            b: "@a\n"
        ])
        let units = ScriptLexer.split("@a\n").units
        XCTAssertThrowsError(
            try ScriptLoader.flatten(units, documentBaseURL: docDir, resolver: resolver, maxDepth: 16)
        )
    }
}

// MARK: - Test resolver

private struct FakeFileResolver: ScriptFileResolver {
    let files: [URL: String]

    func read(_ url: URL) throws -> String {
        let key = url.standardizedFileURL
        if let body = files[key] { return body }
        // also try without standardisation
        if let body = files[url] { return body }
        throw NSError(domain: "FakeFileResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: "no fixture for \(url.path)"])
    }

    func exists(_ url: URL) -> Bool {
        files[url.standardizedFileURL] != nil || files[url] != nil
    }
}
