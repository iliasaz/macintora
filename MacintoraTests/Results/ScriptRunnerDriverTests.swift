//
//  ScriptRunnerDriverTests.swift
//  MacintoraTests
//
//  Drives the runner with a scripted fake executor and asserts the event
//  stream's order/content. Phase 4 will land a separate live integration
//  test against a real `c4-local` connection.
//

import XCTest
@testable import Macintora

final class ScriptRunnerDriverTests: XCTestCase {

    func test_single_unit_success_emits_started_finished_done() async {
        let units = lex("select 1 from dual;")
        XCTAssertEqual(units.count, 1)

        let executor = FakeConnectionExecutor(responses: [
            .success(UnitResult(
                outcome: .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil),
                elapsed: .zero
            ))
        ])

        let events = await collect(units: units, executor: executor)

        XCTAssertEqual(events.count, 3)
        guard case .unitStarted(0, 1, let u) = events[0] else { return XCTFail("expected unitStarted") }
        XCTAssertEqual(u.text, "select 1 from dual")
        guard case .unitFinished(0, let r) = events[1] else { return XCTFail("expected unitFinished") }
        XCTAssertEqual(r.outcome, .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil))
        guard case .scriptFinished = events[2] else { return XCTFail("expected scriptFinished") }

        let executions = await executor.observedExecutions()
        XCTAssertEqual(executions.count, 1)
        XCTAssertEqual(executions[0].resolvedText, "select 1 from dual")
    }

    func test_single_unit_failure_short_circuits_when_whenever_exit() async {
        let units = lex("select bad;\nselect 1 from dual;")
        XCTAssertEqual(units.count, 2)

        let executor = FakeConnectionExecutor(responses: [
            .failure(NSError(domain: "ora", code: 942, userInfo: [NSLocalizedDescriptionKey: "ORA-00942: table or view does not exist"]))
        ])

        let env = SqlPlusEnvironment()
        env.whenever = .exit(.failure, commitOrRollback: nil)

        let runner = ScriptRunner(units: units, executor: executor, env: env)
        var events: [ScriptRunnerEvent] = []
        for await ev in runner.start() { events.append(ev) }

        // 1: unitStarted(0), 2: unitFinished(0,failed), 3: scriptFinished
        XCTAssertEqual(events.count, 3)
        guard case .unitFinished(0, let r) = events[1] else { return XCTFail("expected unitFinished") }
        if case .statementFailed(let msg, _) = r.outcome {
            XCTAssertTrue(msg.contains("ORA-00942") || msg.contains("table or view"))
        } else {
            XCTFail("expected statementFailed")
        }

        let executions = await executor.observedExecutions()
        XCTAssertEqual(executions.count, 1, "second unit should not have run")
    }

    func test_failure_continues_when_whenever_continue() async {
        let units = lex("select bad;\nselect 1 from dual;")
        let executor = FakeConnectionExecutor(responses: [
            .failure(NSError(domain: "ora", code: 942)),
            .success(UnitResult(outcome: .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil), elapsed: .zero))
        ])

        // Default env has WHENEVER SQLERROR CONTINUE.
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())
        var collected: [ScriptRunnerEvent] = []
        for await ev in runner.start() {
            collected.append(ev)
        }

        // started(0), finished(0,fail), started(1), finished(1,success), done
        XCTAssertEqual(collected.count, 5)
        if case .unitFinished(_, let r) = collected[3] {
            XCTAssertEqual(r.outcome, .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil))
        } else {
            XCTFail("expected unitFinished for second unit")
        }
        let executions = await executor.observedExecutions()
        XCTAssertEqual(executions.count, 2)
    }

    func test_cancellation_emits_cancelled_event() async {
        let units = lex("""
            select 1 from dual;
            select 2 from dual;
            select 3 from dual;
            """)
        let executor = FakeConnectionExecutor(responses: [
            .success(UnitResult(outcome: .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil), elapsed: .zero)),
            .delayedSuccess(forever: true)
        ])

        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())
        let stream = runner.start()
        var collected: [ScriptRunnerEvent] = []

        let consumer = Task {
            for await ev in stream {
                collected.append(ev)
                if case .unitFinished(0, _) = ev {
                    Task { await runner.cancel() }
                }
            }
            return collected
        }

        let final = await consumer.value
        // started(0) + finished(0) + started(1) + cancelled — order may interleave
        // but the last emitted event before stream end must be `cancelled`.
        XCTAssertTrue(final.contains(where: { if case .cancelled = $0 { return true }; return false }),
                      "expected a cancelled event, got: \(final)")
        // No scriptFinished after cancellation.
        XCTAssertFalse(final.contains(where: { if case .scriptFinished = $0 { return true }; return false }))
    }

    func test_whenever_exit_takes_effect_when_set_mid_script() async {
        // Unit 0 fails — env still defaults to CONTINUE, so we proceed.
        // Unit 1 sets WHENEVER SQLERROR EXIT.
        // Unit 2 fails — now we should halt before unit 3.
        let units = lex("""
            select bad_one from dual;
            WHENEVER SQLERROR EXIT FAILURE
            select bad_two from dual;
            select 'never reached' from dual;
            """)
        XCTAssertEqual(units.count, 4)

        let executor = FakeConnectionExecutor(responses: [
            .failure(NSError(domain: "ora", code: 942)),
            .failure(NSError(domain: "ora", code: 942)),
        ])

        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())
        var collected: [ScriptRunnerEvent] = []
        for await ev in runner.start() { collected.append(ev) }

        let outcomes = collected.compactMap { event -> UnitResult.Outcome? in
            if case .unitFinished(_, let r) = event { return r.outcome }
            return nil
        }
        XCTAssertEqual(outcomes.count, 3, "expected 3 finished units (two failures + one directive), got: \(outcomes)")
        if case .statementFailed = outcomes[0] {} else { XCTFail("first should fail") }
        if case .directiveAcknowledged = outcomes[1] {} else { XCTFail("WHENEVER should ack as directive") }
        if case .statementFailed = outcomes[2] {} else { XCTFail("third should fail") }

        let executions = await executor.observedExecutions()
        XCTAssertEqual(executions.count, 2, "fourth unit must not run after WHENEVER EXIT halts")
    }

    func test_define_mid_script_substitutes_subsequent_units() async {
        // Unit 0: DEFINE owner = hr
        // Unit 1: SELECT * FROM &owner..t  → resolved text "SELECT * FROM hr.t"
        let units = lex("""
            DEFINE owner = hr
            SELECT * FROM &owner..t;
            """)
        let executor = FakeConnectionExecutor(responses: [
            .success(UnitResult(outcome: .statementSucceeded(rowCount: 0, dbmsOutput: [], preview: nil), elapsed: .zero)),
        ])
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())
        for await _ in runner.start() {}

        let executions = await executor.observedExecutions()
        XCTAssertEqual(executions.count, 1)
        XCTAssertEqual(executions[0].resolvedText, "SELECT * FROM hr.t")
    }

    func test_needsBinds_event_is_emitted_for_units_with_colon_binds() async {
        let units = lex("select * from emp where id = :id;")
        let executor = FakeConnectionExecutor(responses: [
            .success(UnitResult(outcome: .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil), elapsed: .zero))
        ])
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())

        var collected: [ScriptRunnerEvent] = []
        for await ev in runner.start() {
            collected.append(ev)
            if case .needsBinds(let request) = ev {
                XCTAssertEqual(request.names, [":id"])
                request.resume([":id": .int(42)])
            }
        }

        let executions = await executor.observedExecutions()
        XCTAssertEqual(executions.count, 1)
        XCTAssertEqual(executions[0].binds[":id"], .int(42))
    }

    func test_needsBinds_resume_nil_cancels_the_run() async {
        let units = lex("""
            select * from emp where id = :id;
            select 'never reached' from dual;
            """)
        let executor = FakeConnectionExecutor(responses: [])
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())

        var sawCancelled = false
        for await ev in runner.start() {
            if case .needsBinds(let request) = ev {
                request.resume(nil)
            }
            if case .cancelled = ev { sawCancelled = true }
        }
        XCTAssertTrue(sawCancelled)
        let executions = await executor.observedExecutions()
        XCTAssertTrue(executions.isEmpty, "no unit should have run when bind prompt was cancelled")
    }

    func test_show_errors_after_create_emits_compile_errors_entry() async {
        let units = lex("""
            CREATE OR REPLACE PROCEDURE p IS BEGIN xx; END;
            /
            SHOW ERRORS
            """)
        XCTAssertEqual(units.count, 2, "lexer should split into PL/SQL block + SHOW ERRORS directive")

        let executor = FakeConnectionExecutor(responses: [
            .success(UnitResult(outcome: .statementSucceeded(rowCount: nil, dbmsOutput: [], preview: nil), elapsed: .zero))
        ])
        let target = CompileErrorTarget(owner: nil, name: "P", type: "PROCEDURE")
        await executor.setCompileErrors(for: target, [
            CompileErrorRow(line: 1, position: 24, sequence: 1, attribute: "ERROR", text: "PLS-00201: identifier 'XX' must be declared")
        ])

        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())
        var compileEntry: (CompileErrorTarget?, [CompileErrorRow])?
        for await ev in runner.start() {
            if case .unitFinished(_, let r) = ev,
               case .directiveCompileErrors(let t, let errs) = r.outcome {
                compileEntry = (t, errs)
            }
        }
        XCTAssertNotNil(compileEntry)
        XCTAssertEqual(compileEntry?.0, target)
        XCTAssertEqual(compileEntry?.1.first?.text, "PLS-00201: identifier 'XX' must be declared")
    }

    func test_show_errors_without_prior_create_emits_empty_entry() async {
        let units = lex("SHOW ERRORS")
        let executor = FakeConnectionExecutor(responses: [])
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())

        var entries: [UnitResult.Outcome] = []
        for await ev in runner.start() {
            if case .unitFinished(_, let r) = ev { entries.append(r.outcome) }
        }
        XCTAssertEqual(entries.count, 1)
        if case .directiveCompileErrors(let target, let errs) = entries[0] {
            XCTAssertNil(target)
            XCTAssertTrue(errs.isEmpty)
        } else {
            XCTFail("expected directiveCompileErrors")
        }
    }

    func test_dbms_output_passes_through_unmodified() async {
        let units = lex("BEGIN DBMS_OUTPUT.PUT_LINE('hi'); END;\n/")
        let executor = FakeConnectionExecutor(responses: [
            .success(UnitResult(outcome: .statementSucceeded(rowCount: nil, dbmsOutput: ["hi"], preview: nil), elapsed: .zero))
        ])

        let events = await collect(units: units, executor: executor)
        guard case .unitFinished(_, let r) = events[1] else { return XCTFail() }
        XCTAssertEqual(r.outcome, .statementSucceeded(rowCount: nil, dbmsOutput: ["hi"], preview: nil))
    }

    // MARK: - Helpers

    private func lex(_ source: String) -> [CommandUnit] {
        ScriptLexer.split(source).units
    }

    private func collect(units: [CommandUnit], executor: any ConnectionExecutor) async -> [ScriptRunnerEvent] {
        let runner = ScriptRunner(units: units, executor: executor, env: SqlPlusEnvironment())
        var events: [ScriptRunnerEvent] = []
        for await ev in runner.start() {
            events.append(ev)
        }
        return events
    }
}

// MARK: - Fake executor

actor FakeConnectionExecutor: ConnectionExecutor {
    enum Response: Sendable {
        case success(UnitResult)
        case failure(Error)
        case delayedSuccess(forever: Bool)
    }

    private var responses: [Response]
    private var executions: [PreparedUnit] = []
    private var cancelled = false
    /// `SHOW ERRORS` returns the canned rows for the matching target.
    var compileErrorsByTarget: [CompileErrorTarget: [CompileErrorRow]] = [:]

    init(responses: [Response]) {
        self.responses = responses
    }

    func fetchCompileErrors(for target: CompileErrorTarget) async throws -> [CompileErrorRow] {
        compileErrorsByTarget[target] ?? []
    }

    func setCompileErrors(for target: CompileErrorTarget, _ rows: [CompileErrorRow]) {
        compileErrorsByTarget[target] = rows
    }

    func execute(_ prepared: PreparedUnit) async throws -> UnitResult {
        executions.append(prepared)
        guard !responses.isEmpty else {
            return UnitResult(outcome: .statementSucceeded(rowCount: 0, dbmsOutput: [], preview: nil), elapsed: .zero)
        }
        let next = responses.removeFirst()
        switch next {
        case .success(let r):
            return r
        case .failure(let e):
            throw e
        case .delayedSuccess(let forever):
            // Sleep until cancelled.
            while !cancelled && !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(20))
                if !forever { break }
            }
            throw CancellationError()
        }
    }

    func cancel() {
        cancelled = true
    }

    func observedExecutions() -> [PreparedUnit] {
        executions
    }
}
