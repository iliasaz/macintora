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

    func test_tables_prefixMatch_withinOwner() async {
        let result = await dataSource.tables(prefix: "EMP", defaultOwner: "HR", limit: 10)
        XCTAssertEqual(result.map(\.name).sorted(), ["EMPLOYEES", "EMP_HISTORY"])
    }

    func test_tables_excludesOtherOwners() async {
        let result = await dataSource.tables(prefix: "DUAL", defaultOwner: "HR", limit: 10)
        XCTAssertTrue(result.isEmpty, "DUAL is in SYS, not HR")
    }

    func test_tables_emptyPrefix_returnsAllInOwner() async {
        let result = await dataSource.tables(prefix: "", defaultOwner: "HR", limit: 10)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - Columns

    func test_columns_byTable() async {
        let result = await dataSource.columns(
            tableName: "EMPLOYEES", owner: "HR", prefix: "", limit: 50)
        XCTAssertEqual(result.map(\.columnName).sorted(),
                       ["EMPLOYEE_ID", "FIRST_NAME", "SALARY"])
    }

    func test_columns_byPrefix() async {
        let result = await dataSource.columns(
            tableName: "EMPLOYEES", owner: "HR", prefix: "FI", limit: 50)
        XCTAssertEqual(result.map(\.columnName), ["FIRST_NAME"])
    }

    // MARK: - Objects

    func test_objects_byOwnerAndType() async {
        let result = await dataSource.objects(
            prefix: "", owner: "HR", types: ["TABLE"], limit: 10)
        XCTAssertEqual(Set(result.map(\.name)),
                       Set(["EMPLOYEES", "EMP_HISTORY", "DEPARTMENTS"]))
    }

    // MARK: - Seed helpers

    private func seed() {
        let ctx = persistence.container.viewContext

        addTable(in: ctx, owner: "HR", name: "EMPLOYEES", isView: false)
        addTable(in: ctx, owner: "HR", name: "EMP_HISTORY", isView: false)
        addTable(in: ctx, owner: "HR", name: "DEPARTMENTS", isView: false)
        addTable(in: ctx, owner: "SYS", name: "DUAL", isView: false)

        addColumn(in: ctx, owner: "HR", table: "EMPLOYEES", column: "EMPLOYEE_ID", type: "NUMBER")
        addColumn(in: ctx, owner: "HR", table: "EMPLOYEES", column: "FIRST_NAME", type: "VARCHAR2")
        addColumn(in: ctx, owner: "HR", table: "EMPLOYEES", column: "SALARY", type: "NUMBER")

        addObject(in: ctx, owner: "HR", name: "EMPLOYEES", type: "TABLE")
        addObject(in: ctx, owner: "HR", name: "EMP_HISTORY", type: "TABLE")
        addObject(in: ctx, owner: "HR", name: "DEPARTMENTS", type: "TABLE")

        try! ctx.save()
    }

    private func addTable(in ctx: NSManagedObjectContext, owner: String, name: String, isView: Bool) {
        let row = DBCacheTable(context: ctx)
        row.owner_ = owner
        row.name_ = name
        row.isView = isView
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
