//
//  ScriptOutputModelTests.swift
//  MacintoraTests
//

import XCTest
@testable import Macintora

@MainActor
final class ScriptOutputModelTests: XCTestCase {

    func test_initial_state_is_empty_and_idle() {
        let model = ScriptOutputModel()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.currentUnitIndex)
        XCTAssertEqual(model.totalUnits, 0)
    }

    func test_beginRun_clears_and_sets_running() {
        let model = ScriptOutputModel()
        model.append(.note(.init(id: UUID(), kind: .info, text: "leftover")))
        model.beginRun(totalUnits: 3)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.totalUnits, 3)
    }

    func test_finishRun_clears_running_state() {
        let model = ScriptOutputModel()
        model.beginRun(totalUnits: 1)
        model.setCurrentUnit(0)
        model.finishRun()
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.currentUnitIndex)
    }

    func test_append_preserves_ordering() {
        let model = ScriptOutputModel()
        let a = ScriptOutputEntry.directive(.init(id: UUID(), text: "SET SERVEROUTPUT ON", elapsed: .zero))
        let b = ScriptOutputEntry.succeeded(.init(
            id: UUID(),
            unitIndex: 0,
            text: "select 1 from dual",
            kind: .sql,
            elapsed: .milliseconds(2),
            rowCount: 1,
            dbmsOutput: [],
            preview: nil
        ))
        let c = ScriptOutputEntry.failed(.init(
            id: UUID(),
            unitIndex: 1,
            text: "select * from nope",
            kind: .sql,
            elapsed: .milliseconds(3),
            message: "ORA-00942",
            oracleErrorCode: 942,
            originalUTF16Range: nil
        ))
        model.append(a)
        model.append(b)
        model.append(c)
        XCTAssertEqual(model.entries.map(\.id), [a.id, b.id, c.id])
    }

    func test_note_helper_appends_note_entry() {
        let model = ScriptOutputModel()
        model.note(.cancelled, text: "User stopped the run.")
        XCTAssertEqual(model.entries.count, 1)
        if case .note(let note) = model.entries[0] {
            XCTAssertEqual(note.kind, .cancelled)
            XCTAssertEqual(note.text, "User stopped the run.")
        } else {
            XCTFail("expected note entry")
        }
    }

    func test_unitKind_initializer_drops_directive_payload() {
        XCTAssertEqual(UnitKind(.sql), .sql)
        XCTAssertEqual(UnitKind(.plsqlBlock), .plsqlBlock)
        XCTAssertEqual(UnitKind(.sqlplus(.showErrors)), .sqlplus)
        XCTAssertEqual(UnitKind(.sqlplus(.set(.serverOutput(true)))), .sqlplus)
    }

    func test_clear_resets_state() {
        let model = ScriptOutputModel()
        model.beginRun(totalUnits: 5)
        model.setCurrentUnit(2)
        model.note(.info, text: "x")
        model.clear()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.totalUnits, 0)
        XCTAssertNil(model.currentUnitIndex)
    }
}

extension ScriptOutputEntry {
    static func == (lhs: ScriptOutputEntry, rhs: ScriptOutputEntry) -> Bool {
        lhs.id == rhs.id
    }
}
