import XCTest
@testable import Macintora

final class DisplayRowTests: XCTestCase {
    func test_sortKeyOrdering_number() {
        let a: DisplayRow.SortKey = .number(1)
        let b: DisplayRow.SortKey = .number(2)
        XCTAssertTrue(a < b)
        XCTAssertFalse(b < a)
    }

    func test_sortKeyOrdering_nullSortsFirst() {
        let null: DisplayRow.SortKey = .null
        let value: DisplayRow.SortKey = .text("z")
        XCTAssertTrue(null < value)
        XCTAssertFalse(value < null)
    }

    func test_sortKeyOrdering_textLocaleAware() {
        let apple: DisplayRow.SortKey = .text("apple")
        let banana: DisplayRow.SortKey = .text("Banana")
        // Locale-aware sort puts apple before Banana.
        XCTAssertTrue(apple < banana)
    }

    func test_displayFieldSubscripts() {
        let row = DisplayRow(id: 0, fields: [
            DisplayField(name: "ID", valueString: "42", sortKey: .number(42)),
            DisplayField(name: "NAME", valueString: "hello", sortKey: .text("hello")),
            DisplayField(name: "BORN", valueString: "2020-01-02 03:04:05", sortKey: .date(Date(timeIntervalSince1970: 0))),
            DisplayField(name: "NULLCOL", valueString: "(null)", sortKey: .null)
        ])

        XCTAssertEqual(row["ID"]?.int, 42)
        XCTAssertEqual(row["NAME"]?.string, "hello")
        XCTAssertEqual(row["NULLCOL"]?.isNull, true)
        XCTAssertNotNil(row["BORN"]?.date)
        XCTAssertEqual(row[0]?.name, "ID")
        XCTAssertEqual(row[1]?.valueString, "hello")
        XCTAssertNil(row[10])
    }

    func test_lessByColumnIndex() {
        let a = DisplayRow(id: 0, fields: [
            DisplayField(name: "N", valueString: "1", sortKey: .number(1))
        ])
        let b = DisplayRow(id: 1, fields: [
            DisplayField(name: "N", valueString: "2", sortKey: .number(2))
        ])
        XCTAssertTrue(DisplayRow.less(colIndex: 0, lhs: a, rhs: b))
        XCTAssertFalse(DisplayRow.less(colIndex: 0, lhs: b, rhs: a))
    }

    func test_lessWithOutOfRangeIndex() {
        let a = DisplayRow(id: 0, fields: [
            DisplayField(name: "N", valueString: "1", sortKey: .number(1))
        ])
        let b = DisplayRow(id: 1, fields: [
            DisplayField(name: "N", valueString: "2", sortKey: .number(2))
        ])
        // out-of-range index -> both nulls -> equal (< false)
        XCTAssertFalse(DisplayRow.less(colIndex: 10, lhs: a, rhs: b))
    }
}
