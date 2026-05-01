//
//  SqlPlusInterpreterTests.swift
//  MacintoraTests
//

import XCTest
@testable import Macintora

final class SqlPlusInterpreterTests: XCTestCase {

    func test_define_inserts_uppercased_key() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(.define(name: "owner", value: "hr"), env: env)
        XCTAssertEqual(outcome, .acknowledged)
        XCTAssertEqual(env.defines["OWNER"], "hr")
    }

    func test_undefine_removes_key() {
        let env = SqlPlusEnvironment()
        env.defines["OWNER"] = "hr"
        _ = SqlPlusInterpreter.apply(.undefine(name: "owner"), env: env)
        XCTAssertNil(env.defines["OWNER"])
    }

    func test_set_serveroutput_toggles() {
        let env = SqlPlusEnvironment()
        env.serverOutput = true
        _ = SqlPlusInterpreter.apply(.set(.serverOutput(false)), env: env)
        XCTAssertFalse(env.serverOutput)
        _ = SqlPlusInterpreter.apply(.set(.serverOutput(true)), env: env)
        XCTAssertTrue(env.serverOutput)
    }

    func test_set_define_off_disables_substitution() {
        let env = SqlPlusEnvironment()
        XCTAssertTrue(env.defineEnabled)
        _ = SqlPlusInterpreter.apply(.set(.define(.off)), env: env)
        XCTAssertFalse(env.defineEnabled)
        _ = SqlPlusInterpreter.apply(.set(.define(.on)), env: env)
        XCTAssertTrue(env.defineEnabled)
    }

    func test_set_define_prefix_changes_character() {
        let env = SqlPlusEnvironment()
        _ = SqlPlusInterpreter.apply(.set(.define(.prefix("#"))), env: env)
        XCTAssertEqual(env.definePrefix, "#")
        XCTAssertTrue(env.defineEnabled)
    }

    func test_prompt_returns_message_outcome() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(.prompt(message: "hello"), env: env)
        XCTAssertEqual(outcome, .prompt(message: "hello"))
    }

    func test_remark_returns_skip() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(.remark(text: "hi"), env: env)
        XCTAssertEqual(outcome, .skip)
    }

    func test_show_errors_returns_showErrors() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(.showErrors, env: env)
        XCTAssertEqual(outcome, .showErrors)
    }

    func test_whenever_sqlerror_exit_records_action() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(
            .whenever(.sqlError, .exit(.failure, commitOrRollback: nil)),
            env: env
        )
        XCTAssertEqual(outcome, .acknowledged)
        XCTAssertEqual(env.whenever, .exit(.failure, commitOrRollback: nil))
    }

    func test_include_returns_unresolved() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(.include(path: "f.sql", doubleAt: false), env: env)
        XCTAssertEqual(outcome, .unresolvedInclude(path: "f.sql", doubleAt: false))
    }

    func test_unrecognized_returns_noted() {
        let env = SqlPlusEnvironment()
        let outcome = SqlPlusInterpreter.apply(.unrecognized(text: "WHATEVER"), env: env)
        XCTAssertEqual(outcome, .noted(text: "WHATEVER"))
    }
}
