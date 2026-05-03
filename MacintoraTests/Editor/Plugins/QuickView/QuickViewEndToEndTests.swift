//
//  QuickViewEndToEndTests.swift
//  MacintoraTests
//
//  Wires the full Quick View pipeline against an in-memory DB cache for
//  every supported object type. For each type we:
//    1. Seed `DBCacheObject` plus the type-specific child entities.
//    2. Run `QuickViewController.fetchPayload(for:preferredOwner:dataSource:)`
//       — the production routing brain.
//    3. Assert the payload's user-facing fields match the seeded data.
//    4. Force-render `QuickViewContent` so the SwiftUI tree actually
//       evaluates with that payload (catches missing types or trapping
//       unwraps that synthetic-fixture render tests would miss).
//
//  Where `QuickViewControllerTests` covers branch logic and
//  `QuickViewContentRenderTests` covers rendering with synthesized data,
//  this suite proves cache → payload → SwiftUI works for real seeded
//  rows of each supported `OracleObjectType`.
//

import XCTest
import AppKit
import SwiftUI
import CoreData
@testable import Macintora

@MainActor
final class QuickViewEndToEndTests: XCTestCase {

    private var persistence: PersistenceController!
    private var dataSource: CompletionDataSource!

    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
        dataSource = CompletionDataSource(persistenceController: persistence)
    }

    override func tearDown() async throws {
        dataSource = nil
        persistence = nil
        try await super.tearDown()
    }

    // MARK: - TABLE

    func test_endToEnd_table_rendersColumnsIndexesTriggers() async {
        seedTable(owner: "HR", name: "EMPLOYEES")
        seedIndex(owner: "HR", table: "EMPLOYEES", name: "EMP_PK", isUnique: true)
        seedTrigger(tableOwner: "HR", tableName: "EMPLOYEES",
                    name: "EMP_AUDIT_TRG", event: "UPDATE", enabled: true)

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "EMPLOYEES"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .table(let table) = payload else {
            return XCTFail("expected .table for a seeded TABLE row, got \(payload)")
        }
        XCTAssertFalse(table.isView)
        XCTAssertEqual(table.columns.map(\.columnName).sorted(),
                       ["EMPLOYEE_ID", "FIRST_NAME", "SALARY"])
        XCTAssertEqual(table.indexes.map(\.name), ["EMP_PK"])
        XCTAssertEqual(table.triggers.map(\.name), ["EMP_AUDIT_TRG"])
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - VIEW

    func test_endToEnd_view_rendersSqlAndColumns() async {
        seedView(owner: "HR", name: "ACTIVE_EMPLOYEES",
                 sql: "SELECT * FROM employees WHERE active = 1")

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "ACTIVE_EMPLOYEES"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .table(let view) = payload else {
            return XCTFail("expected .table (view shape) for VIEW, got \(payload)")
        }
        XCTAssertTrue(view.isView)
        XCTAssertEqual(view.sqlText, "SELECT * FROM employees WHERE active = 1")
        XCTAssertFalse(view.columns.isEmpty,
                       "View payload must include cached column metadata")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - PACKAGE

    func test_endToEnd_package_rendersMembersAndOverloads() async {
        seedAccountsPackage()

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "ACCOUNTS_PKG"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .packageOrType(let pkg) = payload else {
            return XCTFail("expected .packageOrType for PACKAGE, got \(payload)")
        }
        XCTAssertEqual(pkg.objectType, "PACKAGE")
        // GET_BALANCE function + DEBIT overload "1" + DEBIT overload "2".
        XCTAssertEqual(pkg.procedures.count, 3)
        let getBalance = pkg.procedures.first { $0.name == "GET_BALANCE" }
        XCTAssertEqual(getBalance?.kind, "FUNCTION")
        XCTAssertEqual(getBalance?.returnType, "NUMBER")
        let debit2 = pkg.procedures.first {
            $0.name == "DEBIT" && $0.overload == "2"
        }
        XCTAssertEqual(debit2?.parameters.count, 2)
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - TYPE

    func test_endToEnd_userDefinedType_rendersAsPackage() async {
        addObject(owner: "HR", name: "ADDRESS_T", type: "TYPE")
        try! persistence.container.viewContext.save()

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "ADDRESS_T"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .packageOrType(let pkg) = payload else {
            return XCTFail("expected .packageOrType for TYPE, got \(payload)")
        }
        XCTAssertEqual(pkg.objectType, "TYPE")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - Standalone PROCEDURE

    func test_endToEnd_standaloneProcedure_rendersSignature() async {
        addObject(owner: "BILLING", name: "RUN_REPORT", type: "PROCEDURE")
        seedStandaloneProcedure(owner: "BILLING", name: "RUN_REPORT",
                                arguments: [("DATE_ARG", "DATE"), ("DETAILED", "BOOLEAN")])

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "BILLING", name: "RUN_REPORT"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure for PROCEDURE, got \(payload)")
        }
        XCTAssertEqual(proc.kind, "PROCEDURE")
        XCTAssertNil(proc.packageName,
                     "Standalone procedure has no parent package")
        XCTAssertEqual(proc.parameters.map(\.name), ["DATE_ARG", "DETAILED"])
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - Standalone FUNCTION

    func test_endToEnd_standaloneFunction_rendersReturnType() async {
        addObject(owner: "HR", name: "SALARY_GRADE", type: "FUNCTION")
        seedStandaloneFunction(owner: "HR", name: "SALARY_GRADE",
                               returnType: "VARCHAR2",
                               arguments: [("AMOUNT", "NUMBER")])

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "SALARY_GRADE"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure for FUNCTION, got \(payload)")
        }
        XCTAssertEqual(proc.kind, "FUNCTION")
        XCTAssertEqual(proc.returnType, "VARCHAR2")
        XCTAssertEqual(proc.parameters.map(\.name), ["AMOUNT"])
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - INDEX (catch-all)

    func test_endToEnd_index_rendersAsUnknownObject() async {
        let ctx = persistence.container.viewContext
        let row = DBCacheObject(context: ctx)
        row.owner_ = "HR"
        row.name_ = "EMP_PK"
        row.type_ = "INDEX"
        row.isValid = true
        row.lastDDLDate = Date(timeIntervalSince1970: 1_700_000_000)
        try! ctx.save()

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "EMP_PK"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .unknownObject(let unknown) = payload else {
            return XCTFail("expected .unknownObject for INDEX, got \(payload)")
        }
        XCTAssertEqual(unknown.objectType, "INDEX")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - SYNONYM (no-chase, v1)

    func test_endToEnd_synonym_rendersAsUnknownObject() async {
        addObject(owner: "PUBLIC", name: "EMP", type: "SYNONYM")
        try! persistence.container.viewContext.save()

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "PUBLIC", name: "EMP"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .unknownObject(let unknown) = payload else {
            return XCTFail("expected .unknownObject for SYNONYM, got \(payload)")
        }
        XCTAssertEqual(unknown.objectType, "SYNONYM")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - TRIGGER (catch-all)

    func test_endToEnd_trigger_rendersAsUnknownObject() async {
        addObject(owner: "HR", name: "EMP_AUDIT_TRG", type: "TRIGGER")
        try! persistence.container.viewContext.save()

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "EMP_AUDIT_TRG"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .unknownObject(let unknown) = payload else {
            return XCTFail("expected .unknownObject for TRIGGER, got \(payload)")
        }
        XCTAssertEqual(unknown.objectType, "TRIGGER")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - COLUMN reference (the alias-resolved path)

    func test_endToEnd_column_rendersColumnPopover() async {
        seedTable(owner: "HR", name: "EMPLOYEES")

        let payload = await QuickViewController.fetchPayload(
            for: .column(tableOwner: "HR",
                         tableName: "EMPLOYEES",
                         columnName: "SALARY"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .column(let col) = payload else {
            return XCTFail("expected .column for column reference, got \(payload)")
        }
        XCTAssertEqual(col.column.columnName, "SALARY")
        XCTAssertEqual(col.column.dataTypeFormatted, "NUMBER(10,2)")
        XCTAssertFalse(col.column.isNullable)
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - PACKAGE MEMBER call (e.g. dbms_output.put_line)

    func test_endToEnd_packageMember_rendersProcedurePopover() async {
        seedAccountsPackage()

        let payload = await QuickViewController.fetchPayload(
            for: .packageMember(packageOwner: "HR",
                                packageName: "ACCOUNTS_PKG",
                                memberName: "GET_BALANCE"),
            preferredOwner: "HR",
            dataSource: dataSource)

        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure for package member, got \(payload)")
        }
        XCTAssertEqual(proc.packageName, "ACCOUNTS_PKG")
        XCTAssertEqual(proc.kind, "FUNCTION")
        XCTAssertEqual(proc.returnType, "NUMBER")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - Cache miss (the "not cached" path)

    func test_endToEnd_cacheMiss_rendersNotCachedPlaceholder() async {
        // Don't seed anything. The popover must still render — its job is to
        // tell the user the object isn't cached.
        let reference = ResolvedDBReference.schemaObject(
            owner: "HR", name: "GHOST")
        let payload = await QuickViewController.fetchPayload(
            for: reference, preferredOwner: "HR",
            dataSource: dataSource)

        guard case .notCached(let echoed) = payload else {
            return XCTFail("expected .notCached, got \(payload)")
        }
        XCTAssertEqual(echoed, reference,
                       "notCached must echo the original reference so the placeholder can render the name")
        XCTAssertNoThrow(try render(payload))
    }

    // MARK: - Render harness

    /// Hosts `QuickViewContent(payload:)` inside an `NSHostingView`, forces
    /// layout, and reads `fittingSize` so the body actually evaluates.
    /// Throwing wrapper means a SwiftUI runtime trap on the main thread
    /// will surface as a test failure rather than silently passing.
    private func render(_ payload: QuickViewPayload) throws {
        let view = QuickViewContent(payload: payload, openInBrowserAction: {})
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
    }

    // MARK: - Seed helpers

    private func seedTable(owner: String, name: String) {
        let ctx = persistence.container.viewContext
        addObject(owner: owner, name: name, type: "TABLE")
        let table = DBCacheTable(context: ctx)
        table.owner_ = owner
        table.name_ = name
        table.isView = false
        table.numRows = 12

        addColumn(owner: owner, table: name, column: "EMPLOYEE_ID",
                  type: "NUMBER", precision: 6, scale: 0,
                  isNullable: false, columnID: 1)
        addColumn(owner: owner, table: name, column: "FIRST_NAME",
                  type: "VARCHAR2", precision: 0, scale: 0,
                  isNullable: true, columnID: 2, length: 120)
        addColumn(owner: owner, table: name, column: "SALARY",
                  type: "NUMBER", precision: 10, scale: 2,
                  isNullable: false, columnID: 3)

        try! ctx.save()
    }

    private func seedView(owner: String, name: String, sql: String) {
        let ctx = persistence.container.viewContext
        addObject(owner: owner, name: name, type: "VIEW")
        let view = DBCacheTable(context: ctx)
        view.owner_ = owner
        view.name_ = name
        view.isView = true
        view.sqltext = sql

        addColumn(owner: owner, table: name, column: "EMPLOYEE_ID",
                  type: "NUMBER", precision: 6, scale: 0,
                  isNullable: false, columnID: 1)
        addColumn(owner: owner, table: name, column: "FIRST_NAME",
                  type: "VARCHAR2", precision: 0, scale: 0,
                  isNullable: true, columnID: 2, length: 120)

        try! ctx.save()
    }

    private func seedIndex(owner: String, table: String, name: String, isUnique: Bool) {
        let ctx = persistence.container.viewContext
        let row = DBCacheIndex(context: ctx)
        row.owner_ = owner
        row.name_ = name
        row.tableOwner_ = owner
        row.tableName_ = table
        row.isUnique = isUnique
        row.isValid = true
        row.type_ = "NORMAL"
        try! ctx.save()
    }

    private func seedTrigger(tableOwner: String, tableName: String,
                             name: String, event: String, enabled: Bool) {
        let ctx = persistence.container.viewContext
        let row = DBCacheTrigger(context: ctx)
        row.owner_ = tableOwner
        row.name_ = name
        row.objectOwner = tableOwner
        row.objectName = tableName
        row.event_ = event
        row.isEnabled = enabled
        try! ctx.save()
    }

    private func seedAccountsPackage() {
        addObject(owner: "HR", name: "ACCOUNTS_PKG", type: "PACKAGE")

        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: nil,
                     subprogramId: 0, overload: nil, parentType: "PACKAGE")
        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: "GET_BALANCE",
                     subprogramId: 1, overload: nil, parentType: "PACKAGE")
        // Distinct subprogram_id per overload — matches Oracle's
        // ALL_PROCEDURES and avoids non-deterministic sort-tie ordering.
        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: "DEBIT",
                     subprogramId: 2, overload: "1", parentType: "PACKAGE")
        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: "DEBIT",
                     subprogramId: 3, overload: "2", parentType: "PACKAGE")

        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 0, sequence: 1, name: nil,
                    dataType: "NUMBER", inOut: "OUT")
        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 1, sequence: 2, name: "ACCT_ID",
                    dataType: "NUMBER", inOut: "IN")

        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "1", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")

        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "2", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")
        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "2", position: 2, sequence: 2, name: "CURRENCY",
                    dataType: "VARCHAR2", inOut: "IN")

        try! persistence.container.viewContext.save()
    }

    private func seedStandaloneFunction(owner: String, name: String,
                                        returnType: String,
                                        arguments: [(String, String)]) {
        addProcedure(owner: owner, pkg: name, name: name,
                     subprogramId: 1, overload: nil, parentType: "FUNCTION")
        addArgument(owner: owner, pkg: name, proc: name,
                    overload: nil, position: 0, sequence: 1,
                    name: nil, dataType: returnType, inOut: "OUT")
        for (i, arg) in arguments.enumerated() {
            addArgument(owner: owner, pkg: name, proc: name,
                        overload: nil, position: Int16(i + 1),
                        sequence: Int16(i + 2),
                        name: arg.0, dataType: arg.1, inOut: "IN")
        }
        try! persistence.container.viewContext.save()
    }

    private func seedStandaloneProcedure(owner: String, name: String,
                                         arguments: [(String, String)]) {
        addProcedure(owner: owner, pkg: name, name: name,
                     subprogramId: 1, overload: nil, parentType: "PROCEDURE")
        for (i, arg) in arguments.enumerated() {
            addArgument(owner: owner, pkg: name, proc: name,
                        overload: nil, position: Int16(i + 1),
                        sequence: Int16(i + 1),
                        name: arg.0, dataType: arg.1, inOut: "IN")
        }
        try! persistence.container.viewContext.save()
    }

    // MARK: - Low-level seed helpers

    private func addObject(owner: String, name: String, type: String) {
        let row = DBCacheObject(context: persistence.container.viewContext)
        row.owner_ = owner
        row.name_ = name
        row.type_ = type
        row.isValid = true
    }

    private func addColumn(owner: String, table: String, column: String,
                           type: String, precision: Int32, scale: Int32,
                           isNullable: Bool, columnID: Int,
                           length: Int32 = 0) {
        let row = DBCacheTableColumn(context: persistence.container.viewContext)
        row.owner_ = owner
        row.tableName_ = table
        row.columnName_ = column
        row.dataType_ = type
        row.precision = precision == 0 ? nil : NSNumber(value: precision)
        row.scale = scale == 0 ? nil : NSNumber(value: scale)
        row.isNullable = isNullable
        row.columnID = NSNumber(value: columnID)
        row.internalColumnID = Int16(columnID)
        row.length = length
    }

    private func addProcedure(owner: String, pkg: String, name: String?,
                              subprogramId: Int32, overload: String?,
                              parentType: String) {
        let row = DBCacheProcedure(context: persistence.container.viewContext)
        row.owner_ = owner
        row.objectName_ = pkg
        row.procedureName_ = name
        row.objectType_ = parentType
        row.subprogramId = subprogramId
        row.overload_ = overload
    }

    private func addArgument(owner: String, pkg: String, proc: String,
                             overload: String?, position: Int16, sequence: Int16,
                             name: String?, dataType: String, inOut: String) {
        let row = DBCacheProcedureArgument(context: persistence.container.viewContext)
        row.owner_ = owner
        row.objectName_ = pkg
        row.procedureName_ = proc
        row.overload_ = overload
        row.position = position
        row.sequence = sequence
        row.dataLevel = 0
        row.argumentName_ = name
        row.dataType_ = dataType
        row.inOut_ = inOut
    }
}
