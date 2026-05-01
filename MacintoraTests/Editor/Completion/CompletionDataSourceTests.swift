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
}
