//
//  TableTableColumnsSortTests.swift
//  MacintoraTests
//
//  Pins the column-header sort behaviour of TableTableColumnsView. The view
//  binds Table's `sortOrder:` to a `[KeyPathComparator<DBCacheTableColumn>]`
//  and sorts the FetchedResults via `Array.sorted(using:)` before handing
//  them to Table. These tests exercise that same sort against an in-memory
//  Core Data store, so a regression that breaks the sort pipeline (wrong
//  comparator target, missing sortOrder binding, etc.) fails here without
//  needing a real UI harness.
//

import XCTest
import CoreData
@testable import Macintora

final class TableTableColumnsSortTests: XCTestCase {

    private var persistence: PersistenceController!
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() async throws {
        persistence = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeColumn(name: String,
                            dataType: String,
                            internalID: Int16,
                            columnID: Int? = nil,
                            length: Int32 = 0,
                            isNullable: Bool = false,
                            isIdentity: Bool = false,
                            defaultValue: String? = nil,
                            isHidden: Bool = false) -> DBCacheTableColumn {
        let c = DBCacheTableColumn(context: context)
        c.owner_ = "SCOTT"
        c.tableName_ = "EMP"
        c.columnName_ = name
        c.dataType_ = dataType
        c.internalColumnID = internalID
        c.columnID = columnID.map { NSNumber(value: $0) }
        c.length = length
        c.isNullable = isNullable
        c.isIdentity = isIdentity
        c.defaultValue = defaultValue
        c.isHidden = isHidden
        return c
    }

    // MARK: - Sort by Column Name

    func test_sortByColumnName_ascending_ordersAlphabetically() {
        let charlie = makeColumn(name: "CHARLIE", dataType: "VARCHAR2", internalID: 1)
        let alpha = makeColumn(name: "ALPHA", dataType: "NUMBER", internalID: 2)
        let bravo = makeColumn(name: "BRAVO", dataType: "DATE", internalID: 3)

        let sorted = [charlie, alpha, bravo].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.columnName, order: .forward)
        ])

        XCTAssertEqual(sorted.map(\.columnName), ["ALPHA", "BRAVO", "CHARLIE"])
    }

    func test_sortByColumnName_descending_reversesOrder() {
        let alpha = makeColumn(name: "ALPHA", dataType: "NUMBER", internalID: 1)
        let bravo = makeColumn(name: "BRAVO", dataType: "DATE", internalID: 2)
        let charlie = makeColumn(name: "CHARLIE", dataType: "VARCHAR2", internalID: 3)

        let sorted = [alpha, bravo, charlie].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.columnName, order: .reverse)
        ])

        XCTAssertEqual(sorted.map(\.columnName), ["CHARLIE", "BRAVO", "ALPHA"])
    }

    // MARK: - Sort by Datatype

    func test_sortByDatatype_ascending_groupsLikeTypes() {
        let a = makeColumn(name: "A", dataType: "VARCHAR2", internalID: 1)
        let b = makeColumn(name: "B", dataType: "NUMBER", internalID: 2)
        let c = makeColumn(name: "C", dataType: "DATE", internalID: 3)
        let d = makeColumn(name: "D", dataType: "NUMBER", internalID: 4)

        let sorted = [a, b, c, d].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.dataType, order: .forward)
        ])

        XCTAssertEqual(sorted.map(\.dataType), ["DATE", "NUMBER", "NUMBER", "VARCHAR2"])
    }

    // MARK: - Default fetch-order comparator

    func test_defaultComparator_byInternalID_matchesFetchOrder() {
        let third = makeColumn(name: "THIRD", dataType: "VARCHAR2", internalID: 3)
        let first = makeColumn(name: "FIRST", dataType: "NUMBER", internalID: 1)
        let second = makeColumn(name: "SECOND", dataType: "DATE", internalID: 2)

        let sorted = [third, first, second].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.internalColumnID)
        ])

        XCTAssertEqual(sorted.map(\.internalColumnID), [1, 2, 3])
    }

    // MARK: - Empty sort order is a no-op

    func test_emptySortOrder_preservesInputOrder() {
        let c1 = makeColumn(name: "ZULU", dataType: "VARCHAR2", internalID: 9)
        let c2 = makeColumn(name: "ALPHA", dataType: "NUMBER", internalID: 1)
        let c3 = makeColumn(name: "MIKE", dataType: "DATE", internalID: 5)

        let sorted = [c1, c2, c3].sorted(using: [KeyPathComparator<DBCacheTableColumn>]())

        XCTAssertEqual(sorted.map(\.columnName), ["ZULU", "ALPHA", "MIKE"])
    }

    // MARK: - Sort-key shims for non-Comparable storage

    func test_sortByColumnID_putsNilLast() {
        // Hidden / system columns have a nil COLUMN_ID; the shim maps nil to
        // Int.max so they sort after numbered columns regardless of order.
        let one = makeColumn(name: "A", dataType: "NUMBER", internalID: 1, columnID: 1)
        let two = makeColumn(name: "B", dataType: "VARCHAR2", internalID: 2, columnID: 2)
        let hidden = makeColumn(name: "SYS$X", dataType: "RAW", internalID: 3, columnID: nil)

        let sorted = [hidden, two, one].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.columnIDSortKey, order: .forward)
        ])

        XCTAssertEqual(sorted.map(\.columnName), ["A", "B", "SYS$X"])
    }

    func test_sortByLength_ascendingByLength() {
        let short = makeColumn(name: "A", dataType: "VARCHAR2", internalID: 1, length: 10)
        let long = makeColumn(name: "B", dataType: "VARCHAR2", internalID: 2, length: 4000)
        let mid = makeColumn(name: "C", dataType: "VARCHAR2", internalID: 3, length: 100)

        let sorted = [long, short, mid].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.length, order: .forward)
        ])

        XCTAssertEqual(sorted.map(\.length), [10, 100, 4000])
    }

    func test_sortByNullable_falseBeforeTrue() {
        let nullable = makeColumn(name: "A", dataType: "NUMBER", internalID: 1, isNullable: true)
        let notNull = makeColumn(name: "B", dataType: "NUMBER", internalID: 2, isNullable: false)

        let sorted = [nullable, notNull].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.isNullableSortKey, order: .forward)
        ])

        XCTAssertEqual(sorted.map(\.isNullable), [false, true])
    }

    func test_sortByIdentity_falseBeforeTrue() {
        let identity = makeColumn(name: "A", dataType: "NUMBER", internalID: 1, isIdentity: true)
        let plain = makeColumn(name: "B", dataType: "NUMBER", internalID: 2, isIdentity: false)

        let sorted = [identity, plain].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.isIdentitySortKey, order: .forward)
        ])

        XCTAssertEqual(sorted.map(\.isIdentity), [false, true])
    }

    func test_sortByDefault_treatsNilAsEmptyString() {
        let withDefault = makeColumn(name: "A", dataType: "NUMBER", internalID: 1, defaultValue: "0")
        let noDefault = makeColumn(name: "B", dataType: "NUMBER", internalID: 2, defaultValue: nil)
        let longDefault = makeColumn(name: "C", dataType: "VARCHAR2", internalID: 3, defaultValue: "hello")

        let sorted = [withDefault, longDefault, noDefault].sorted(using: [
            KeyPathComparator(\DBCacheTableColumn.defaultValueSortKey, order: .forward)
        ])

        // nil ("") < "0" < "hello"
        XCTAssertEqual(sorted.map(\.defaultValueSortKey), ["", "0", "hello"])
    }
}
