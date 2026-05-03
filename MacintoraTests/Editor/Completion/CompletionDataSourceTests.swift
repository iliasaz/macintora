//
//  CompletionDataSourceTests.swift
//  MacintoraTests
//
//  Exercises `CompletionDataSource` against an in-memory CoreData store seeded
//  with a handful of `DBCacheTable`/`DBCacheTableColumn`/`DBCacheObject` rows.
//  Verifies prefix matching, owner filtering, and case-insensitive lookup.
//

import XCTest
import CoreData
@testable import Macintora

@MainActor
final class CompletionDataSourceTests: XCTestCase {

    private var persistence: PersistenceController!
    private var dataSource: CompletionDataSource!

    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
        seed()
        dataSource = CompletionDataSource(persistenceController: persistence)
    }

    override func tearDown() async throws {
        dataSource = nil
        persistence = nil
        try await super.tearDown()
    }

    // MARK: - Tables

    func test_tables_substringMatch_acrossSchemas() async {
        // Substring match: "EMP" hits EMPLOYEES, EMP_HISTORY (HR) and
        // BILLING.EMP_BILLS. All returned, HR rows ranked first.
        let result = await dataSource.tables(search: "EMP", preferredOwner: "HR", limit: 10)
        XCTAssertEqual(Set(result.map(\.name)),
                       Set(["EMPLOYEES", "EMP_HISTORY", "EMP_BILLS"]))
        // First entries belong to the preferred owner.
        let firstTwoOwners = Array(result.prefix(2)).map(\.owner)
        XCTAssertTrue(firstTwoOwners.allSatisfy { $0 == "HR" })
    }

    func test_tables_includesOtherOwners() async {
        let result = await dataSource.tables(search: "DUAL", preferredOwner: "HR", limit: 10)
        XCTAssertEqual(result.map(\.name), ["DUAL"], "Cross-schema lookup must surface SYS.DUAL")
        XCTAssertEqual(result.first?.owner, "SYS")
    }

    func test_tables_emptySearch_returnsPreferredOwnerOnly() async {
        let result = await dataSource.tables(search: "", preferredOwner: "HR", limit: 10)
        XCTAssertEqual(result.count, 3, "Empty search must scope to preferred owner to avoid cache dump")
    }

    func test_tables_caseInsensitive() async {
        let result = await dataSource.tables(search: "emP", preferredOwner: "HR", limit: 10)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains { $0.name == "EMPLOYEES" })
    }

    func test_tables_prefixRanksAboveInfix() async {
        // EMP_BILLS is a prefix match; XYZ_EMP would be an infix match if it
        // existed — verify by adding one.
        addObject(in: persistence.container.viewContext,
                  owner: "HR", name: "XYZ_EMP_LOG", type: "TABLE")
        try! persistence.container.viewContext.save()

        let result = await dataSource.tables(search: "EMP", preferredOwner: "HR", limit: 10)
        let names = result.map(\.name)
        XCTAssertTrue(names.contains("XYZ_EMP_LOG"))
        // All prefix-matching names appear before any infix-only name.
        let lastPrefix = names.lastIndex(where: { $0.uppercased().hasPrefix("EMP") }) ?? -1
        let firstInfix = names.firstIndex(of: "XYZ_EMP_LOG") ?? Int.max
        XCTAssertLessThan(lastPrefix, firstInfix, "Prefix matches must rank before infix-only matches")
    }

    // MARK: - Columns

    func test_columns_byTable() async {
        let result = await dataSource.columns(
            tableName: "EMPLOYEES", owner: "HR", search: "", limit: 50)
        XCTAssertEqual(result.map(\.columnName).sorted(),
                       ["EMPLOYEE_ID", "FIRST_NAME", "SALARY"])
    }

    func test_columns_substringMatch() async {
        let result = await dataSource.columns(
            tableName: "EMPLOYEES", owner: "HR", search: "ID", limit: 50)
        // EMPLOYEE_ID is the only column containing "ID".
        XCTAssertEqual(result.map(\.columnName), ["EMPLOYEE_ID"])
    }

    // MARK: - Objects

    func test_objects_byOwnerAndType() async {
        let result = await dataSource.objects(
            search: "", owner: "HR", types: ["TABLE"], limit: 10)
        XCTAssertEqual(Set(result.map(\.name)),
                       Set(["EMPLOYEES", "EMP_HISTORY", "DEPARTMENTS"]))
    }

    func test_objects_substringAcrossSchemas() async {
        let result = await dataSource.objects(
            search: "EMP", owner: nil, preferredOwner: "HR",
            types: ["TABLE"], limit: 10)
        XCTAssertTrue(result.contains { $0.owner == "HR" && $0.name == "EMPLOYEES" })
        XCTAssertTrue(result.contains { $0.owner == "BILLING" && $0.name == "EMP_BILLS" })
        XCTAssertEqual(result.first?.owner, "HR")
    }

    // MARK: - Procedures

    func test_procedures_listsPackageMembers_skipsSelfRow() async {
        seedAccountsPackage()
        let result = await dataSource.procedures(
            packageName: "ACCOUNTS_PKG", owner: "HR", search: "", limit: 10)
        // Three subprograms: get_balance (function), debit (procedure with two
        // overloads). The SUBPROGRAM_ID = 0 self-row is excluded.
        XCTAssertEqual(Set(result.map(\.procedureName)), Set(["GET_BALANCE", "DEBIT"]))
    }

    func test_procedures_classifiesFunctionByReturnRow() async {
        seedAccountsPackage()
        let result = await dataSource.procedures(
            packageName: "ACCOUNTS_PKG", owner: "HR", search: "GET", limit: 10)
        let getBalance = result.first { $0.procedureName == "GET_BALANCE" }
        XCTAssertEqual(getBalance?.kind, "FUNCTION")
        XCTAssertEqual(getBalance?.returnType, "NUMBER")
    }

    func test_procedures_classifiesProcedureWhenNoReturnRow() async {
        seedAccountsPackage()
        let result = await dataSource.procedures(
            packageName: "ACCOUNTS_PKG", owner: "HR", search: "DEBIT", limit: 10)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.allSatisfy { $0.kind == "PROCEDURE" })
        XCTAssertTrue(result.allSatisfy { $0.returnType == nil })
    }

    func test_procedureArguments_filtersByOverload_excludesReturnRow() async {
        seedAccountsPackage()
        let args = await dataSource.procedureArguments(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "DEBIT", overload: "1")
        // Overload 1 has a single AMOUNT parameter; overload 2 has two.
        XCTAssertEqual(args.map(\.argumentName), ["AMOUNT"])
        XCTAssertTrue(args.allSatisfy { $0.position > 0 })
    }

    // MARK: - Quick View: resolveSchemaObject

    func test_resolveSchemaObject_explicitOwner_findsExactRow() async {
        let resolved = await dataSource.resolveSchemaObject(
            owner: "HR", name: "EMPLOYEES", preferredOwner: "")
        XCTAssertEqual(resolved?.owner, "HR")
        XCTAssertEqual(resolved?.name, "EMPLOYEES")
        XCTAssertEqual(resolved?.objectType, "TABLE")
    }

    func test_resolveSchemaObject_caseInsensitive() async {
        // Lowercase input — the cache stores upper-case names, the resolver
        // must normalise.
        let resolved = await dataSource.resolveSchemaObject(
            owner: "hr", name: "employees", preferredOwner: "")
        XCTAssertEqual(resolved?.owner, "HR")
        XCTAssertEqual(resolved?.name, "EMPLOYEES")
    }

    func test_resolveSchemaObject_noOwner_prefersConnectedSchema() async {
        // EMP_BILLS exists only in BILLING; EMPLOYEES exists only in HR.
        // When the cursor lacked a schema qualifier, the connected schema
        // (preferredOwner) wins ties.
        addObject(in: persistence.container.viewContext,
                  owner: "BILLING", name: "EMPLOYEES", type: "VIEW")
        try! persistence.container.viewContext.save()

        let resolved = await dataSource.resolveSchemaObject(
            owner: nil, name: "EMPLOYEES", preferredOwner: "HR")
        XCTAssertEqual(resolved?.owner, "HR",
                       "Tie between HR.EMPLOYEES and BILLING.EMPLOYEES must resolve to the connected schema")
    }

    func test_resolveSchemaObject_returnsNilForUnknown() async {
        let resolved = await dataSource.resolveSchemaObject(
            owner: "HR", name: "DOES_NOT_EXIST", preferredOwner: "")
        XCTAssertNil(resolved)
    }

    // MARK: - Quick View: tableDetail

    func test_tableDetail_assemblesColumnsIndexesTriggers() async {
        seedEmployeesTableExtras()
        guard let detail = await dataSource.tableDetail(
            owner: "HR", name: "EMPLOYEES", highlightedColumn: nil)
        else { return XCTFail("tableDetail returned nil for seeded HR.EMPLOYEES") }

        XCTAssertFalse(detail.isView)
        XCTAssertEqual(detail.columns.map(\.columnName).sorted(),
                       ["EMPLOYEE_ID", "FIRST_NAME", "SALARY"])
        XCTAssertEqual(detail.indexes.map(\.name), ["EMP_PK"])
        XCTAssertEqual(detail.triggers.map(\.name), ["EMP_AUDIT_TRG"])
        XCTAssertNil(detail.highlightedColumn)
    }

    func test_tableDetail_passesThroughHighlightedColumn() async {
        seedEmployeesTableExtras()
        let detail = await dataSource.tableDetail(
            owner: "HR", name: "EMPLOYEES", highlightedColumn: "salary")
        // Highlighted column is upper-cased so the SwiftUI `id` lookup matches.
        XCTAssertEqual(detail?.highlightedColumn, "SALARY")
    }

    func test_tableDetail_typeFormatting_oracleStyle() async {
        seedEmployeesTableExtras()
        let detail = await dataSource.tableDetail(
            owner: "HR", name: "EMPLOYEES", highlightedColumn: nil)
        let firstName = detail?.columns.first { $0.columnName == "FIRST_NAME" }
        // Seeded with length=120 → VARCHAR2(120).
        XCTAssertEqual(firstName?.dataTypeFormatted, "VARCHAR2(120)")
        let salary = detail?.columns.first { $0.columnName == "SALARY" }
        // Seeded with precision=10, scale=2 → NUMBER(10,2).
        XCTAssertEqual(salary?.dataTypeFormatted, "NUMBER(10,2)")
    }

    func test_tableDetail_view_carriesSqlText() async {
        seedActiveEmployeesView()
        let detail = await dataSource.tableDetail(
            owner: "HR", name: "ACTIVE_EMPLOYEES", highlightedColumn: nil)
        XCTAssertTrue(detail?.isView ?? false)
        XCTAssertEqual(detail?.sqlText, "SELECT * FROM employees WHERE active = 1")
    }

    func test_tableDetail_returnsEmptyContainersForCacheMiss() async {
        // Object exists but no DBCacheTable / column / index / trigger rows.
        addObject(in: persistence.container.viewContext,
                  owner: "HR", name: "BARE_OBJECT", type: "TABLE")
        try! persistence.container.viewContext.save()

        let detail = await dataSource.tableDetail(
            owner: "HR", name: "BARE_OBJECT", highlightedColumn: nil)
        XCTAssertNotNil(detail, "tableDetail returns a payload even when the row is metadata-only")
        XCTAssertTrue(detail?.columns.isEmpty ?? false)
        XCTAssertTrue(detail?.indexes.isEmpty ?? false)
        XCTAssertTrue(detail?.triggers.isEmpty ?? false)
    }

    // MARK: - Quick View: columnDetail

    func test_columnDetail_findsAndPopulatesFlags() async {
        seedEmployeesTableExtras()
        guard let column = await dataSource.columnDetail(
            tableOwner: "HR", tableName: "EMPLOYEES", columnName: "SALARY")
        else { return XCTFail("columnDetail returned nil") }
        XCTAssertEqual(column.column.columnName, "SALARY")
        XCTAssertEqual(column.column.dataTypeFormatted, "NUMBER(10,2)")
        XCTAssertFalse(column.column.isNullable)
    }

    func test_columnDetail_returnsNilForMissingColumn() async {
        seedEmployeesTableExtras()
        let column = await dataSource.columnDetail(
            tableOwner: "HR", tableName: "EMPLOYEES", columnName: "NOPE")
        XCTAssertNil(column)
    }

    // MARK: - Quick View: packageDetail

    func test_packageDetail_assemblesProceduresWithReturnTypes() async {
        seedAccountsPackage()
        guard let pkg = await dataSource.packageDetail(
            owner: "HR", name: "ACCOUNTS_PKG")
        else { return XCTFail("packageDetail returned nil") }

        XCTAssertEqual(pkg.objectType, "PACKAGE")
        let names = pkg.procedures.map(\.name)
        XCTAssertEqual(names.sorted(), ["DEBIT", "DEBIT", "GET_BALANCE"],
                       "Both DEBIT overloads must appear as separate entries")

        let getBalance = pkg.procedures.first { $0.name == "GET_BALANCE" }
        XCTAssertEqual(getBalance?.kind, "FUNCTION")
        XCTAssertEqual(getBalance?.returnType, "NUMBER")
        XCTAssertEqual(getBalance?.parameters.map(\.name) ?? [], ["ACCT_ID"])

        let debitOverload2 = pkg.procedures.first {
            $0.name == "DEBIT" && $0.overload == "2"
        }
        XCTAssertEqual(debitOverload2?.parameters.map(\.name) ?? [], ["AMOUNT", "CURRENCY"])
    }

    func test_packageDetail_skipsPackageSelfRow() async {
        seedAccountsPackage()
        let pkg = await dataSource.packageDetail(owner: "HR", name: "ACCOUNTS_PKG")
        // The SUBPROGRAM_ID = 0 self-row has procedureName_ = nil and must
        // never appear in the rendered list.
        XCTAssertFalse(pkg?.procedures.contains { $0.name.isEmpty } ?? true)
    }

    // MARK: - Quick View: procedureDetail

    func test_procedureDetail_packageMember_pickFirstOverload() async {
        seedAccountsPackage()
        // Both DEBIT overloads exist; passing nil should pick the lowest
        // subprogram_id, matching ALL_PROCEDURES order.
        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "DEBIT", overload: nil)
        XCTAssertEqual(proc?.kind, "PROCEDURE")
        XCTAssertEqual(proc?.packageName, "ACCOUNTS_PKG")
        // overload "1" has one parameter; "2" has two.
        XCTAssertEqual(proc?.parameters.count, 1)
    }

    func test_procedureDetail_packageMember_specificOverload() async {
        seedAccountsPackage()
        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "DEBIT", overload: "2")
        XCTAssertEqual(proc?.parameters.map(\.name), ["AMOUNT", "CURRENCY"])
    }

    func test_procedureDetail_function_carriesReturnType() async {
        seedAccountsPackage()
        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "GET_BALANCE", overload: nil)
        XCTAssertEqual(proc?.kind, "FUNCTION")
        XCTAssertEqual(proc?.returnType, "NUMBER")
    }

    func test_procedureDetail_returnsNilForUnknownMember() async {
        seedAccountsPackage()
        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "NOPE", overload: nil)
        XCTAssertNil(proc)
    }

    func test_procedureDetail_packageMember_propagatesParentInvalidity() async {
        seedAccountsPackage()
        let ctx = persistence.container.viewContext
        addObject(in: ctx, owner: "HR", name: "ACCOUNTS_PKG", type: "PACKAGE")
        // Last-seeded object wins under our addObject helper — flip isValid
        // by editing the row we just created.
        let request = DBCacheObject.fetchRequest()
        request.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                        "HR", "ACCOUNTS_PKG")
        let row = try! ctx.fetch(request).first
        row?.isValid = false
        try! ctx.save()

        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "DEBIT", overload: nil)
        XCTAssertNotNil(proc)
        XCTAssertFalse(proc?.isValid ?? true)
    }

    func test_procedureDetail_standalone_propagatesObjectInvalidity() async {
        let ctx = persistence.container.viewContext
        // Standalone PROCEDURE — parent object is keyed by the procedure name.
        addProcedure(in: ctx, owner: "HR", pkg: "PURGE_OLD", name: "PURGE_OLD",
                     subprogramId: 1, overload: nil, parentType: "PROCEDURE")
        addObject(in: ctx, owner: "HR", name: "PURGE_OLD", type: "PROCEDURE")
        let request = DBCacheObject.fetchRequest()
        request.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                        "HR", "PURGE_OLD")
        let row = try! ctx.fetch(request).first
        row?.isValid = false
        try! ctx.save()

        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: nil,
            procedureName: "PURGE_OLD", overload: nil)
        XCTAssertNotNil(proc)
        XCTAssertFalse(proc?.isValid ?? true)
    }

    func test_procedureDetail_defaultsToValidWhenParentObjectMissing() async {
        // Existing fixture has no DBCacheObject for ACCOUNTS_PKG — the
        // fallback should keep isValid = true so we don't false-positive.
        seedAccountsPackage()
        let proc = await dataSource.procedureDetail(
            owner: "HR", packageName: "ACCOUNTS_PKG",
            procedureName: "DEBIT", overload: nil)
        XCTAssertTrue(proc?.isValid ?? false)
    }

    // MARK: - Quick View: unknownObjectDetail

    func test_unknownObjectDetail_carriesObjectMetadata() async {
        let ctx = persistence.container.viewContext
        let row = DBCacheObject(context: ctx)
        row.owner_ = "HR"
        row.name_ = "EMP_PK"
        row.type_ = "INDEX"
        row.isValid = true
        row.lastDDLDate = Date(timeIntervalSince1970: 1_700_000_000)
        try! ctx.save()

        let payload = await dataSource.unknownObjectDetail(owner: "HR", name: "EMP_PK")
        XCTAssertEqual(payload?.objectType, "INDEX")
        XCTAssertEqual(payload?.lastDDLDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(payload?.isValid ?? false)
    }

    // MARK: - Seed helpers

    private func seed() {
        let ctx = persistence.container.viewContext

        // tables() now reads from DBCacheObject (the comprehensive catalog).
        // DBCacheTable rows would be ignored, so seed via DBCacheObject only.
        addObject(in: ctx, owner: "HR", name: "EMPLOYEES", type: "TABLE")
        addObject(in: ctx, owner: "HR", name: "EMP_HISTORY", type: "TABLE")
        addObject(in: ctx, owner: "HR", name: "DEPARTMENTS", type: "TABLE")
        addObject(in: ctx, owner: "SYS", name: "DUAL", type: "TABLE")
        // BILLING.EMP_BILLS exercises cross-schema substring matching: the
        // user is connected as HR but has access to BILLING via grant.
        addObject(in: ctx, owner: "BILLING", name: "EMP_BILLS", type: "TABLE")

        addColumn(in: ctx, owner: "HR", table: "EMPLOYEES", column: "EMPLOYEE_ID", type: "NUMBER")
        addColumn(in: ctx, owner: "HR", table: "EMPLOYEES", column: "FIRST_NAME", type: "VARCHAR2")
        addColumn(in: ctx, owner: "HR", table: "EMPLOYEES", column: "SALARY", type: "NUMBER")

        try! ctx.save()
    }

    private func addColumn(in ctx: NSManagedObjectContext,
                           owner: String, table: String, column: String, type: String) {
        let row = DBCacheTableColumn(context: ctx)
        row.owner_ = owner
        row.tableName_ = table
        row.columnName_ = column
        row.dataType_ = type
    }

    private func addObject(in ctx: NSManagedObjectContext,
                           owner: String, name: String, type: String) {
        let row = DBCacheObject(context: ctx)
        row.owner_ = owner
        row.name_ = name
        row.type_ = type
    }

    /// Seeds a package `HR.ACCOUNTS_PKG` with three subprograms:
    /// - `GET_BALANCE` (FUNCTION): return NUMBER, one IN parameter ACCT_ID.
    /// - `DEBIT` overload 1 (PROCEDURE): one IN parameter AMOUNT.
    /// - `DEBIT` overload 2 (PROCEDURE): two parameters AMOUNT and CURRENCY.
    /// Plus a SUBPROGRAM_ID=0 self-row that the data source must skip.
    private func seedAccountsPackage() {
        let ctx = persistence.container.viewContext

        addProcedure(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG",
                     name: nil, subprogramId: 0, overload: nil,
                     parentType: "PACKAGE")
        addProcedure(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG",
                     name: "GET_BALANCE", subprogramId: 1, overload: nil,
                     parentType: "PACKAGE")
        // Distinct subprogram_id per overload — Oracle gives each overload
        // a unique value in ALL_PROCEDURES, and our sort-by-subprogramId
        // picker breaks ties non-deterministically when they collide,
        // which made `pickFirstOverload` flaky on cold full-suite runs.
        addProcedure(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG",
                     name: "DEBIT", subprogramId: 2, overload: "1",
                     parentType: "PACKAGE")
        addProcedure(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG",
                     name: "DEBIT", subprogramId: 3, overload: "2",
                     parentType: "PACKAGE")

        // GET_BALANCE return row + IN parameter.
        addArgument(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 0, sequence: 1, name: nil,
                    dataType: "NUMBER", inOut: "OUT")
        addArgument(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 1, sequence: 2, name: "ACCT_ID",
                    dataType: "NUMBER", inOut: "IN")

        // DEBIT overload 1 — single parameter.
        addArgument(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "1", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")

        // DEBIT overload 2 — two parameters.
        addArgument(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "2", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")
        addArgument(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "2", position: 2, sequence: 2, name: "CURRENCY",
                    dataType: "VARCHAR2", inOut: "IN")

        try! ctx.save()
    }

    private func addProcedure(in ctx: NSManagedObjectContext,
                              owner: String, pkg: String, name: String?,
                              subprogramId: Int32, overload: String?,
                              parentType: String) {
        let row = DBCacheProcedure(context: ctx)
        row.owner_ = owner
        row.objectName_ = pkg
        row.procedureName_ = name
        row.objectType_ = parentType
        row.subprogramId = subprogramId
        row.overload_ = overload
    }

    private func addArgument(in ctx: NSManagedObjectContext,
                             owner: String, pkg: String, proc: String,
                             overload: String?, position: Int16, sequence: Int16,
                             name: String?, dataType: String, inOut: String) {
        let row = DBCacheProcedureArgument(context: ctx)
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

    /// Seeds the rows the Quick View `tableDetail` fetcher consumes:
    /// a `DBCacheTable` for HR.EMPLOYEES (so isView/sqltext are populated),
    /// fully-typed columns, one index, and one trigger.
    private func seedEmployeesTableExtras() {
        let ctx = persistence.container.viewContext

        let table = DBCacheTable(context: ctx)
        table.owner_ = "HR"
        table.name_ = "EMPLOYEES"
        table.isView = false
        table.isPartitioned = false

        // Replace the bare-bones columns from `seed()` with typed copies so
        // formatDataType has dimensions to render. Delete-then-recreate keeps
        // the test independent of the seed's exact field set.
        let existing = (try? ctx.fetch(DBCacheTableColumn.fetchRequest()))?
            .filter { $0.owner_ == "HR" && $0.tableName_ == "EMPLOYEES" } ?? []
        for column in existing { ctx.delete(column) }

        addTypedColumn(in: ctx, owner: "HR", table: "EMPLOYEES",
                       column: "EMPLOYEE_ID", type: "NUMBER",
                       length: 0, precision: 6, scale: 0,
                       isNullable: false, columnID: 1)
        addTypedColumn(in: ctx, owner: "HR", table: "EMPLOYEES",
                       column: "FIRST_NAME", type: "VARCHAR2",
                       length: 120, precision: 0, scale: 0,
                       isNullable: true, columnID: 2)
        addTypedColumn(in: ctx, owner: "HR", table: "EMPLOYEES",
                       column: "SALARY", type: "NUMBER",
                       length: 0, precision: 10, scale: 2,
                       isNullable: false, columnID: 3)

        let index = DBCacheIndex(context: ctx)
        index.owner_ = "HR"
        index.name_ = "EMP_PK"
        index.tableOwner_ = "HR"
        index.tableName_ = "EMPLOYEES"
        index.isUnique = true
        index.isValid = true
        index.type_ = "NORMAL"

        let trigger = DBCacheTrigger(context: ctx)
        trigger.owner_ = "HR"
        trigger.name_ = "EMP_AUDIT_TRG"
        trigger.objectOwner = "HR"
        trigger.objectName = "EMPLOYEES"
        trigger.event_ = "UPDATE"
        trigger.isEnabled = true

        try! ctx.save()
    }

    /// Seeds an HR.ACTIVE_EMPLOYEES view so `tableDetail` has a row whose
    /// `isView == true` and `sqltext` is populated.
    private func seedActiveEmployeesView() {
        let ctx = persistence.container.viewContext

        addObject(in: ctx, owner: "HR", name: "ACTIVE_EMPLOYEES", type: "VIEW")
        let view = DBCacheTable(context: ctx)
        view.owner_ = "HR"
        view.name_ = "ACTIVE_EMPLOYEES"
        view.isView = true
        view.sqltext = "SELECT * FROM employees WHERE active = 1"

        try! ctx.save()
    }

    private func addTypedColumn(in ctx: NSManagedObjectContext,
                                owner: String, table: String, column: String,
                                type: String, length: Int32,
                                precision: Int32, scale: Int32,
                                isNullable: Bool, columnID: Int) {
        let row = DBCacheTableColumn(context: ctx)
        row.owner_ = owner
        row.tableName_ = table
        row.columnName_ = column
        row.dataType_ = type
        row.length = length
        row.precision = precision == 0 ? nil : NSNumber(value: precision)
        row.scale = scale == 0 ? nil : NSNumber(value: scale)
        row.isNullable = isNullable
        row.columnID = NSNumber(value: columnID)
        row.internalColumnID = Int16(columnID)
    }
}
