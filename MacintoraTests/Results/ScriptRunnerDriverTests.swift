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

    func test_single_unit_failure_short_circuits_when_stopOnError() async {
        let units = lex("select bad;\nselect 1 from dual;")
        XCTAssertEqual(units.count, 2)

        let executor = FakeConnectionExecutor(responses: [
            .failure(NSError(domain: "ora", code: 942, userInfo: [NSLocalizedDescriptionKey: "ORA-00942: table or view does not exist"]))
        ])

        let events = await collect(units: units, executor: executor)

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

    func test_failure_continues_when_stopOnError_disabled() async {
        let units = lex("select bad;\nselect 1 from dual;")
        let executor = FakeConnectionExecutor(responses: [
            .failure(NSError(domain: "ora", code: 942)),
            .success(UnitResult(outcome: .statementSucceeded(rowCount: 1, dbmsOutput: [], preview: nil), elapsed: .zero))
        ])

        let runner = ScriptRunner(units: units, executor: executor, options: .init(stopOnError: false))
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

        let runner = ScriptRunner(units: units, executor: executor)
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
        let runner = ScriptRunner(units: units, executor: executor)
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

    init(responses: [Response]) {
        self.responses = responses
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
