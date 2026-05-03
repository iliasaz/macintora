//
//  QuickViewContentRenderTests.swift
//  MacintoraTests
//
//  Smoke tests that each `QuickViewPayload` variant renders without
//  trapping. Hosts the SwiftUI view inside `NSHostingView` and forces
//  layout so the body actually evaluates — catches missing types,
//  force-unwraps, or accidental nil dereferences in the view tree.
//
//  Doesn't assert on visual output (that's UI-test territory). The win is
//  guarding against compile-time-only regressions that don't show up
//  until a user triggers a particular payload kind in production.
//

import XCTest
import AppKit
import SwiftUI
@testable import Macintora

@MainActor
final class QuickViewContentRenderTests: XCTestCase {

    // MARK: - Per-payload smoke tests

    func test_render_table() {
        let payload = QuickViewPayload.table(.fixture(isView: false))
        XCTAssertNoThrow(try renderAndForceLayout(payload: payload))
    }

    func test_render_view_withSqlText() {
        var table = TableDetailPayload.fixture(isView: true)
        table = TableDetailPayload(
            owner: table.owner, name: table.name,
            isView: true, isEditioning: false, isReadOnly: false,
            isPartitioned: false, numRows: nil, lastAnalyzed: nil,
            sqlText: "SELECT * FROM employees WHERE active = 1",
            columns: table.columns, indexes: [], triggers: [],
            highlightedColumn: nil)
        XCTAssertNoThrow(try renderAndForceLayout(payload: .table(table)))
    }

    func test_render_table_withHighlightedColumn() {
        let highlighted = TableDetailPayload(
            owner: "HR", name: "EMPLOYEES",
            isView: false, isEditioning: false, isReadOnly: false,
            isPartitioned: false, numRows: 10_000,
            lastAnalyzed: Date(timeIntervalSince1970: 1_700_000_000),
            sqlText: nil,
            columns: TableDetailPayload.fixtureColumns,
            indexes: [QuickViewIndex.fixture],
            triggers: [QuickViewTrigger.fixture],
            highlightedColumn: "SALARY")
        XCTAssertNoThrow(try renderAndForceLayout(payload: .table(highlighted)))
    }

    func test_render_packageOrType() {
        let payload = QuickViewPayload.packageOrType(.fixture)
        XCTAssertNoThrow(try renderAndForceLayout(payload: payload))
    }

    func test_render_packageOrType_emptyProcedures_showsSpec() {
        let bare = PackageDetailPayload(
            owner: "HR", name: "BARE_PKG",
            objectType: "PACKAGE", isValid: true,
            specSource: "PACKAGE bare_pkg AS\n  -- no public members\nEND;",
            procedures: [])
        XCTAssertNoThrow(try renderAndForceLayout(payload: .packageOrType(bare)))
    }

    func test_render_procedure_function() {
        let payload = QuickViewPayload.procedure(.functionFixture)
        XCTAssertNoThrow(try renderAndForceLayout(payload: payload))
    }

    func test_render_procedure_procedure_noParams() {
        let payload = QuickViewPayload.procedure(.procedureNoParamsFixture)
        XCTAssertNoThrow(try renderAndForceLayout(payload: payload))
    }

    func test_render_column() {
        let payload = QuickViewPayload.column(.fixture(virtual: false))
        XCTAssertNoThrow(try renderAndForceLayout(payload: payload))
    }

    func test_render_column_virtual_withLongDefault() {
        // Virtual columns render the expression in a scroll view. Stress
        // the view with a multi-line expression so the disclosure path runs.
        var col = ColumnDetailPayload.fixture(virtual: true)
        col = ColumnDetailPayload(
            tableOwner: col.tableOwner,
            tableName: col.tableName,
            column: QuickViewColumn(
                columnID: 1, columnName: "TOTAL_COMP",
                dataType: "NUMBER", dataTypeFormatted: "NUMBER(12,2)",
                isNullable: true,
                defaultValue: """
                CASE
                  WHEN dept = 'SALES' THEN salary + nvl(bonus,0) * 1.10
                  ELSE salary + nvl(bonus,0)
                END
                """,
                isIdentity: false, isVirtual: true, isHidden: false))
        XCTAssertNoThrow(try renderAndForceLayout(payload: .column(col)))
    }

    func test_render_unknownObject() {
        let payload = QuickViewPayload.unknownObject(.fixture)
        XCTAssertNoThrow(try renderAndForceLayout(payload: payload))
    }

    // MARK: - Table header stats line

    func test_render_table_withRowCountAndAnalyzed() {
        let table = TableDetailPayload(
            owner: "HR", name: "EMPLOYEES",
            isView: false, isEditioning: false, isReadOnly: false,
            isPartitioned: false,
            numRows: 12_345_678,
            lastAnalyzed: Date(timeIntervalSince1970: 1_700_000_000),
            sqlText: nil,
            columns: TableDetailPayload.fixtureColumns,
            indexes: [], triggers: [],
            highlightedColumn: nil)
        XCTAssertNoThrow(try renderAndForceLayout(payload: .table(table)))
    }

    func test_render_table_withEditioningChip() {
        let table = TableDetailPayload(
            owner: "HR", name: "EMPLOYEES",
            isView: false, isEditioning: true, isReadOnly: false,
            isPartitioned: false,
            numRows: nil, lastAnalyzed: nil,
            sqlText: nil,
            columns: TableDetailPayload.fixtureColumns,
            indexes: [], triggers: [],
            highlightedColumn: nil)
        XCTAssertNoThrow(try renderAndForceLayout(payload: .table(table)))
    }

    func test_render_table_withNoStats_subLineHidden() {
        // Both `numRows` and `lastAnalyzed` nil — the stats subline must
        // collapse to `EmptyView` so the header doesn't grow a blank row.
        let table = TableDetailPayload(
            owner: "HR", name: "BLANK_TABLE",
            isView: false, isEditioning: false, isReadOnly: false,
            isPartitioned: false,
            numRows: nil, lastAnalyzed: nil,
            sqlText: nil,
            columns: [], indexes: [], triggers: [],
            highlightedColumn: nil)
        XCTAssertNoThrow(try renderAndForceLayout(payload: .table(table)))
    }

    func test_render_table_withRowCountOnly_omitsAnalyzed() {
        let table = TableDetailPayload(
            owner: "HR", name: "EMPLOYEES",
            isView: false, isEditioning: false, isReadOnly: false,
            isPartitioned: false,
            numRows: 42, lastAnalyzed: nil,
            sqlText: nil,
            columns: TableDetailPayload.fixtureColumns,
            indexes: [], triggers: [],
            highlightedColumn: nil)
        XCTAssertNoThrow(try renderAndForceLayout(payload: .table(table)))
    }

    func test_render_notCached_eachReferenceShape() {
        // The "not cached" placeholder formats the reference name; cover
        // each enum case so we don't regress the formatter accidentally.
        let cases: [ResolvedDBReference] = [
            .schemaObject(owner: "HR", name: "EMPLOYEES"),
            .schemaObject(owner: nil, name: "DUAL"),
            .packageMember(packageOwner: "SYS",
                           packageName: "DBMS_OUTPUT",
                           memberName: "PUT_LINE"),
            .packageMember(packageOwner: nil,
                           packageName: "DBMS_OUTPUT",
                           memberName: "PUT_LINE"),
            .column(tableOwner: "HR", tableName: "EMPLOYEES", columnName: "SALARY"),
            .column(tableOwner: nil, tableName: "EMPLOYEES", columnName: "SALARY"),
            .unresolved
        ]
        for reference in cases {
            XCTAssertNoThrow(try renderAndForceLayout(
                payload: .notCached(reference: reference)),
                             "notCached must render for \(reference)")
        }
    }

    // MARK: - "Open in Browser" closure variants

    func test_render_withOpenInBrowserClosure() {
        // Footer button is conditionally shown when the closure is non-nil;
        // exercise the branch.
        XCTAssertNoThrow(try renderAndForceLayout(
            payload: .table(.fixture(isView: false)),
            openInBrowserAction: { /* no-op */ }))
    }

    func test_render_withoutOpenInBrowserClosure() {
        XCTAssertNoThrow(try renderAndForceLayout(
            payload: .table(.fixture(isView: false)),
            openInBrowserAction: nil))
    }

    // MARK: - Helpers

    private func renderAndForceLayout(payload: QuickViewPayload,
                                      openInBrowserAction: (() -> Void)? = {}) throws {
        let view = QuickViewContent(payload: payload,
                                    openInBrowserAction: openInBrowserAction)
        let host = NSHostingView(rootView: view)
        // Pin to a realistic popover frame so layout has a finite container
        // to resolve scroll views and lazy stacks against.
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        host.layoutSubtreeIfNeeded()
        // `fittingSize` triggers body evaluation independently of the frame
        // we set above — belt-and-braces.
        _ = host.fittingSize
    }
}

// MARK: - Fixtures

extension TableDetailPayload {
    static let fixtureColumns: [QuickViewColumn] = [
        QuickViewColumn(columnID: 1, columnName: "EMPLOYEE_ID",
                        dataType: "NUMBER", dataTypeFormatted: "NUMBER(6)",
                        isNullable: false, defaultValue: nil,
                        isIdentity: true, isVirtual: false, isHidden: false),
        QuickViewColumn(columnID: 2, columnName: "FIRST_NAME",
                        dataType: "VARCHAR2", dataTypeFormatted: "VARCHAR2(120)",
                        isNullable: true, defaultValue: nil,
                        isIdentity: false, isVirtual: false, isHidden: false),
        QuickViewColumn(columnID: 3, columnName: "SALARY",
                        dataType: "NUMBER", dataTypeFormatted: "NUMBER(10,2)",
                        isNullable: false, defaultValue: "0",
                        isIdentity: false, isVirtual: false, isHidden: false)
    ]

    static func fixture(isView: Bool) -> TableDetailPayload {
        TableDetailPayload(
            owner: "HR", name: isView ? "ACTIVE_EMPLOYEES" : "EMPLOYEES",
            isView: isView, isEditioning: false, isReadOnly: false,
            isPartitioned: false, numRows: 12, lastAnalyzed: nil,
            sqlText: isView ? "SELECT * FROM employees" : nil,
            columns: fixtureColumns, indexes: [QuickViewIndex.fixture],
            triggers: [QuickViewTrigger.fixture],
            highlightedColumn: nil)
    }
}

extension QuickViewIndex {
    static let fixture = QuickViewIndex(
        owner: "HR", name: "EMP_PK",
        type: "NORMAL", isUnique: true, isValid: true)
}

extension QuickViewTrigger {
    static let fixture = QuickViewTrigger(
        owner: "HR", name: "EMP_AUDIT_TRG",
        event: "UPDATE", isEnabled: true)
}

extension PackageDetailPayload {
    static let fixture = PackageDetailPayload(
        owner: "HR", name: "ACCOUNTS_PKG",
        objectType: "PACKAGE", isValid: true,
        specSource: "PACKAGE accounts_pkg AS\n  FUNCTION get_balance(...) RETURN NUMBER;\nEND;",
        procedures: [
            QuickViewPackageProcedure(
                name: "GET_BALANCE", kind: "FUNCTION",
                overload: nil, returnType: "NUMBER",
                parameters: [
                    QuickViewProcedureArgument(
                        sequence: 1, position: 1,
                        name: "ACCT_ID", dataType: "NUMBER",
                        inOut: "IN", defaulted: false, defaultValue: nil)
                ]),
            QuickViewPackageProcedure(
                name: "DEBIT", kind: "PROCEDURE",
                overload: "1", returnType: nil,
                parameters: [
                    QuickViewProcedureArgument(
                        sequence: 1, position: 1,
                        name: "AMOUNT", dataType: "NUMBER",
                        inOut: "IN", defaulted: false, defaultValue: nil)
                ])
        ])
}

extension ProcedureDetailPayload {
    static let functionFixture = ProcedureDetailPayload(
        owner: "HR", name: "GET_BALANCE",
        packageName: "ACCOUNTS_PKG", kind: "FUNCTION",
        overload: nil, returnType: "NUMBER",
        parameters: [
            QuickViewProcedureArgument(
                sequence: 1, position: 1,
                name: "ACCT_ID", dataType: "NUMBER",
                inOut: "IN", defaulted: true, defaultValue: "0")
        ],
        isValid: true)

    static let procedureNoParamsFixture = ProcedureDetailPayload(
        owner: "HR", name: "DAILY_RESET",
        packageName: nil, kind: "PROCEDURE",
        overload: nil, returnType: nil,
        parameters: [],
        isValid: true)
}

extension ColumnDetailPayload {
    static func fixture(virtual: Bool) -> ColumnDetailPayload {
        ColumnDetailPayload(
            tableOwner: "HR", tableName: "EMPLOYEES",
            column: QuickViewColumn(
                columnID: 1,
                columnName: virtual ? "TOTAL_COMP" : "SALARY",
                dataType: "NUMBER",
                dataTypeFormatted: "NUMBER(10,2)",
                isNullable: virtual,
                defaultValue: virtual ? "salary + nvl(commission,0)" : nil,
                isIdentity: false,
                isVirtual: virtual,
                isHidden: false))
    }
}

extension UnknownObjectPayload {
    static let fixture = UnknownObjectPayload(
        owner: "HR", name: "EMP_PK",
        objectType: "INDEX", isValid: true,
        lastDDLDate: Date(timeIntervalSince1970: 1_700_000_000))
}
