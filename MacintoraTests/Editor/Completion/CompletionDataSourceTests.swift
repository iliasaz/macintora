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
        addProcedure(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG",
                     name: "DEBIT", subprogramId: 2, overload: "1",
                     parentType: "PACKAGE")
        addProcedure(in: ctx, owner: "HR", pkg: "ACCOUNTS_PKG",
                     name: "DEBIT", subprogramId: 2, overload: "2",
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
}
