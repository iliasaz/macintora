//
//  QuickViewControllerTests.swift
//  MacintoraTests
//
//  Exercises `QuickViewController.fetchPayload(for:preferredOwner:dataSource:)`
//  — the routing brain that turns a `ResolvedDBReference` into the right
//  cached `QuickViewPayload` variant. Drives an in-memory CoreData store via
//  `CompletionDataSource` so we cover the full data path that production
//  takes after a trigger fires, minus the AppKit popover layer.
//

import XCTest
import CoreData
@testable import Macintora

@MainActor
final class QuickViewControllerTests: XCTestCase {

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

    // MARK: - schemaObject → table

    func test_schemaObject_table_returnsTablePayload() async {
        seedTable(owner: "HR", name: "EMPLOYEES")
        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "EMPLOYEES"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .table(let table) = payload else {
            return XCTFail("expected .table, got \(payload)")
        }
        XCTAssertEqual(table.owner, "HR")
        XCTAssertEqual(table.name, "EMPLOYEES")
        XCTAssertFalse(table.isView)
    }

    func test_schemaObject_view_returnsTablePayloadWithIsView() async {
        seedView(owner: "HR", name: "ACTIVE_EMPLOYEES",
                 sql: "SELECT * FROM employees WHERE active = 1")
        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "ACTIVE_EMPLOYEES"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .table(let table) = payload else {
            return XCTFail("expected .table for view payload, got \(payload)")
        }
        XCTAssertTrue(table.isView)
        XCTAssertEqual(table.sqlText, "SELECT * FROM employees WHERE active = 1")
    }

    func test_schemaObject_unqualified_prefersConnectedSchema() async {
        // Two schemas have an EMPLOYEES table; with no owner provided, the
        // controller must defer to the user's connected schema.
        seedTable(owner: "HR", name: "EMPLOYEES")
        seedTable(owner: "BILLING", name: "EMPLOYEES")

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: nil, name: "EMPLOYEES"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .table(let table) = payload else {
            return XCTFail("expected .table, got \(payload)")
        }
        XCTAssertEqual(table.owner, "HR")
    }

    // MARK: - schemaObject → package / type

    func test_schemaObject_package_returnsPackagePayload() async {
        seedAccountsPackage()
        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "ACCOUNTS_PKG"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .packageOrType(let pkg) = payload else {
            return XCTFail("expected .packageOrType, got \(payload)")
        }
        XCTAssertEqual(pkg.objectType, "PACKAGE")
        XCTAssertFalse(pkg.procedures.isEmpty,
                       "package payload must include cached procedures")
    }

    func test_schemaObject_userDefinedType_returnsPackagePayload() async {
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
    }

    // MARK: - schemaObject → standalone procedure / function

    func test_schemaObject_standaloneFunction_returnsProcedurePayload() async {
        seedStandaloneFunction(owner: "HR", name: "SALARY_GRADE",
                               returnType: "VARCHAR2",
                               argument: ("AMOUNT", "NUMBER"))
        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "SALARY_GRADE"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure, got \(payload)")
        }
        XCTAssertEqual(proc.kind, "FUNCTION")
        XCTAssertNil(proc.packageName)
        XCTAssertEqual(proc.returnType, "VARCHAR2")
        XCTAssertEqual(proc.parameters.map(\.name), ["AMOUNT"])
    }

    func test_schemaObject_unknownObjectType_returnsUnknownPayload() async {
        addObject(owner: "HR", name: "EMP_PK", type: "INDEX")
        try! persistence.container.viewContext.save()

        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "HR", name: "EMP_PK"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .unknownObject(let unknown) = payload else {
            return XCTFail("expected .unknownObject for INDEX, got \(payload)")
        }
        XCTAssertEqual(unknown.objectType, "INDEX")
    }

    func test_schemaObject_synonym_returnsUnknownPayload() async {
        // Synonyms aren't chased in v1 — the popover shows the synonym row
        // itself with an "Open in Browser" affordance.
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
    }

    // MARK: - schemaObject → not cached

    func test_schemaObject_missing_returnsNotCached() async {
        let reference = ResolvedDBReference.schemaObject(owner: "HR", name: "GHOST")
        let payload = await QuickViewController.fetchPayload(
            for: reference, preferredOwner: "HR", dataSource: dataSource)
        guard case .notCached(let echoed) = payload else {
            return XCTFail("expected .notCached, got \(payload)")
        }
        XCTAssertEqual(echoed, reference,
                       "notCached must echo the original reference so the UI can render its name")
    }

    func test_schemaObject_qualified_fallsBackToPackageMember() async {
        // `schema.proc` interpretation didn't match — a 2-part schemaObject
        // looking like `pkg.proc` must fall through to the package-member
        // probe before declaring the cache empty. Seed a package member
        // matching the second leg.
        seedAccountsPackage()
        let payload = await QuickViewController.fetchPayload(
            for: .schemaObject(owner: "ACCOUNTS_PKG", name: "GET_BALANCE"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure via package-member fallback, got \(payload)")
        }
        XCTAssertEqual(proc.packageName, "ACCOUNTS_PKG")
        XCTAssertEqual(proc.name, "GET_BALANCE")
    }

    // MARK: - packageMember

    func test_packageMember_explicit_returnsProcedurePayload() async {
        seedAccountsPackage()
        let payload = await QuickViewController.fetchPayload(
            for: .packageMember(packageOwner: "HR",
                                packageName: "ACCOUNTS_PKG",
                                memberName: "GET_BALANCE"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure for packageMember, got \(payload)")
        }
        XCTAssertEqual(proc.packageName, "ACCOUNTS_PKG")
        XCTAssertEqual(proc.kind, "FUNCTION")
    }

    func test_packageMember_unqualified_usesPreferredOwner() async {
        seedAccountsPackage()
        let payload = await QuickViewController.fetchPayload(
            for: .packageMember(packageOwner: nil,
                                packageName: "ACCOUNTS_PKG",
                                memberName: "GET_BALANCE"),
            preferredOwner: "HR",
            dataSource: dataSource)
        if case .procedure = payload { return /* OK */ }
        XCTFail("nil packageOwner with preferredOwner=HR should still resolve, got \(payload)")
    }

    func test_packageMember_fallsBackToSchemaWhenNoSuchMember() async {
        // No DBCacheProcedure rows exist; the qualifier was actually a schema
        // and the member is a standalone object. Controller must try the
        // schema-object path before giving up.
        addObject(owner: "BILLING", name: "RUN_REPORT", type: "PROCEDURE")
        seedStandaloneProcedure(owner: "BILLING", name: "RUN_REPORT",
                                argument: ("DATE_ARG", "DATE"))

        let payload = await QuickViewController.fetchPayload(
            for: .packageMember(packageOwner: nil,
                                packageName: "BILLING",
                                memberName: "RUN_REPORT"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .procedure(let proc) = payload else {
            return XCTFail("expected .procedure via schema fallback, got \(payload)")
        }
        XCTAssertEqual(proc.owner, "BILLING")
        XCTAssertNil(proc.packageName)
    }

    func test_packageMember_unresolvable_returnsNotCached() async {
        let reference = ResolvedDBReference.packageMember(
            packageOwner: nil,
            packageName: "GHOST_PKG",
            memberName: "NOPE")
        let payload = await QuickViewController.fetchPayload(
            for: reference, preferredOwner: "HR", dataSource: dataSource)
        guard case .notCached(let echoed) = payload else {
            return XCTFail("expected .notCached, got \(payload)")
        }
        XCTAssertEqual(echoed, reference)
    }

    // MARK: - column

    func test_column_returnsColumnPayload() async {
        seedTable(owner: "HR", name: "EMPLOYEES")
        let payload = await QuickViewController.fetchPayload(
            for: .column(tableOwner: "HR", tableName: "EMPLOYEES", columnName: "SALARY"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .column(let col) = payload else {
            return XCTFail("expected .column, got \(payload)")
        }
        XCTAssertEqual(col.column.columnName, "SALARY")
        XCTAssertEqual(col.tableName, "EMPLOYEES")
    }

    func test_column_unknownColumn_fallsBackToParentTable() async {
        // Table is cached but the specific column row is missing — controller
        // upgrades to a table popover with the missing column "highlighted".
        seedTable(owner: "HR", name: "EMPLOYEES")
        let payload = await QuickViewController.fetchPayload(
            for: .column(tableOwner: "HR", tableName: "EMPLOYEES", columnName: "GHOST"),
            preferredOwner: "HR",
            dataSource: dataSource)
        guard case .table(let table) = payload else {
            return XCTFail("expected .table fallback, got \(payload)")
        }
        XCTAssertEqual(table.highlightedColumn, "GHOST")
    }

    func test_column_unknownTable_returnsNotCached() async {
        let reference = ResolvedDBReference.column(
            tableOwner: "HR",
            tableName: "GHOST",
            columnName: "ANYTHING")
        let payload = await QuickViewController.fetchPayload(
            for: reference, preferredOwner: "HR", dataSource: dataSource)
        guard case .notCached(let echoed) = payload else {
            return XCTFail("expected .notCached, got \(payload)")
        }
        XCTAssertEqual(echoed, reference)
    }

    func test_column_nilOwner_fallsBackToPreferredOwnerForTable() async {
        // The resolver couldn't determine the table owner via alias map, but
        // the column does belong to a cached HR.EMPLOYEES.SALARY. Controller
        // must still succeed.
        seedTable(owner: "HR", name: "EMPLOYEES")
        let payload = await QuickViewController.fetchPayload(
            for: .column(tableOwner: nil, tableName: "EMPLOYEES", columnName: "SALARY"),
            preferredOwner: "HR",
            dataSource: dataSource)
        if case .column = payload { return /* OK */ }
        XCTFail("nil tableOwner with cached HR.EMPLOYEES should resolve, got \(payload)")
    }

    // MARK: - unresolved

    func test_unresolved_returnsNotCached() async {
        let payload = await QuickViewController.fetchPayload(
            for: .unresolved,
            preferredOwner: "HR",
            dataSource: dataSource)
        if case .notCached(.unresolved) = payload { return /* OK */ }
        XCTFail("unresolved must produce .notCached(.unresolved), got \(payload)")
    }

    // MARK: - Seed helpers

    private func seedTable(owner: String, name: String) {
        let ctx = persistence.container.viewContext
        addObject(owner: owner, name: name, type: "TABLE")
        let table = DBCacheTable(context: ctx)
        table.owner_ = owner
        table.name_ = name
        table.isView = false

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
        try! ctx.save()
    }

    private func seedAccountsPackage() {
        let ctx = persistence.container.viewContext
        addObject(owner: "HR", name: "ACCOUNTS_PKG", type: "PACKAGE")

        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: nil,
                     subprogramId: 0, overload: nil, parentType: "PACKAGE")
        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: "GET_BALANCE",
                     subprogramId: 1, overload: nil, parentType: "PACKAGE")
        addProcedure(owner: "HR", pkg: "ACCOUNTS_PKG", name: "DEBIT",
                     subprogramId: 2, overload: "1", parentType: "PACKAGE")

        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 0, sequence: 1, name: nil,
                    dataType: "NUMBER", inOut: "OUT")
        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 1, sequence: 2, name: "ACCT_ID",
                    dataType: "NUMBER", inOut: "IN")
        addArgument(owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "1", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")

        try! ctx.save()
    }

    /// Seeds a standalone function — `objectName_` and `procedureName_`
    /// match (the latter is required by the cache schema even for
    /// standalone subprograms; the data fetcher's
    /// `procedureDetail(packageName: nil, …)` falls back to using the
    /// procedure's own name as the `objectName_`).
    private func seedStandaloneFunction(owner: String, name: String,
                                        returnType: String,
                                        argument: (String, String)) {
        let ctx = persistence.container.viewContext
        addObject(owner: owner, name: name, type: "FUNCTION")

        addProcedure(owner: owner, pkg: name, name: name,
                     subprogramId: 1, overload: nil, parentType: "FUNCTION")
        addArgument(owner: owner, pkg: name, proc: name,
                    overload: nil, position: 0, sequence: 1,
                    name: nil, dataType: returnType, inOut: "OUT")
        addArgument(owner: owner, pkg: name, proc: name,
                    overload: nil, position: 1, sequence: 2,
                    name: argument.0, dataType: argument.1, inOut: "IN")

        try! ctx.save()
    }

    private func seedStandaloneProcedure(owner: String, name: String,
                                         argument: (String, String)) {
        let ctx = persistence.container.viewContext
        addProcedure(owner: owner, pkg: name, name: name,
                     subprogramId: 1, overload: nil, parentType: "PROCEDURE")
        addArgument(owner: owner, pkg: name, proc: name,
                    overload: nil, position: 1, sequence: 1,
                    name: argument.0, dataType: argument.1, inOut: "IN")
        try! persistence.container.viewContext.save()
    }

    // MARK: - Low-level seed helpers (mirror `CompletionDataSourceTests`)

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
