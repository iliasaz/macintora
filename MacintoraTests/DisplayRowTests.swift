import XCTest
import RegexBuilder
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

    // MARK: - formatDate / TimestampDisplayMode

    /// Pinned instant: 2025-04-26 04:38:00 UTC.
    private static let testInstant = Date(timeIntervalSince1970: 1_745_642_280)

    private func makeReferenceFormatter(timeZone: TimeZone, includeOffset: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        var options: ISO8601DateFormatter.Options = [
            .withFullDate, .withTime,
            .withDashSeparatorInDate, .withColonSeparatorInTime,
            .withSpaceBetweenDateAndTime
        ]
        if includeOffset { options.insert(.withTimeZone) }
        f.formatOptions = options
        f.timeZone = timeZone
        return f
    }

    func test_formatDate_utcMode_alwaysUTCWithOffset() {
        let expected = makeReferenceFormatter(
            timeZone: TimeZone(secondsFromGMT: 0)!, includeOffset: true
        ).string(from: Self.testInstant)
        for hasTimeZone in [false, true] {
            let result = DisplayRowBuilder.formatDate(
                Self.testInstant, hasTimeZone: hasTimeZone, mode: .utc
            )
            XCTAssertEqual(result, expected, "utc mode should ignore hasTimeZone=\(hasTimeZone)")
        }
    }

    func test_formatDate_localMode_alwaysLocalWithOffset() {
        let expected = makeReferenceFormatter(
            timeZone: .current, includeOffset: true
        ).string(from: Self.testInstant)
        for hasTimeZone in [false, true] {
            let result = DisplayRowBuilder.formatDate(
                Self.testInstant, hasTimeZone: hasTimeZone, mode: .local
            )
            XCTAssertEqual(result, expected, "local mode should ignore hasTimeZone=\(hasTimeZone)")
        }
    }

    func test_formatDate_mixedMode_TZAwareUsesLocal() {
        let expected = makeReferenceFormatter(
            timeZone: .current, includeOffset: true
        ).string(from: Self.testInstant)
        let result = DisplayRowBuilder.formatDate(
            Self.testInstant, hasTimeZone: true, mode: .mixed
        )
        XCTAssertEqual(result, expected, "mixed + hasTimeZone=true should match local-with-offset")
    }

    func test_formatDate_mixedMode_DateAndTimestampUseUTCWithoutOffset() {
        // For DATE / TIMESTAMP, oracle-nio interprets wire bytes as UTC components, so
        // UTC-formatting (no offset shown) reproduces the original stored values.
        let expected = makeReferenceFormatter(
            timeZone: TimeZone(secondsFromGMT: 0)!, includeOffset: false
        ).string(from: Self.testInstant)
        let result = DisplayRowBuilder.formatDate(
            Self.testInstant, hasTimeZone: false, mode: .mixed
        )
        XCTAssertEqual(result, expected, "mixed + hasTimeZone=false should render UTC without offset")
        XCTAssertFalse(result.contains("+"), "DB-time output must not include a TZ offset")
        XCTAssertFalse(result.hasSuffix("Z"), "DB-time output must not include a TZ marker")
    }

    // MARK: - JSONValue / formatJSON

    /// JSONValue decodes from a standard Foundation Decoder (JSONDecoder) and the
    /// `formatJSON` helper round-trips through JSONSerialization. We use a
    /// JSONDecoder here as a stand-in for oracle-nio's OracleJSONDecoder — both are
    /// schema-driven Decoders, so the JSONValue logic is identical from its
    /// perspective. The oracle-nio binary parser is covered upstream.
    private func decodeJSONValue(_ raw: String) throws -> DisplayRowBuilder.JSONValue {
        let data = Data(raw.utf8)
        return try JSONDecoder().decode(DisplayRowBuilder.JSONValue.self, from: data)
    }

    func test_jsonValue_decodesObjectAndRoundTrips() throws {
        let raw = #"{"category":"compute","sub_category":"dedicated_host","cpu":{"architecture":"arm64","number":"8"}}"#
        let value = try decodeJSONValue(raw)
        guard case let .object(top) = value else {
            return XCTFail("expected object, got \(value)")
        }
        XCTAssertEqual(top["category"], .string("compute"))
        XCTAssertEqual(top["sub_category"], .string("dedicated_host"))
        if case let .object(cpu) = top["cpu"] {
            XCTAssertEqual(cpu["architecture"], .string("arm64"))
            XCTAssertEqual(cpu["number"], .string("8"))
        } else {
            XCTFail("expected nested cpu object")
        }
    }

    func test_jsonValue_decodesArrayOfMixedScalars() throws {
        let raw = #"[1, 2.5, "x", true, null]"#
        let value = try decodeJSONValue(raw)
        guard case let .array(items) = value else {
            return XCTFail("expected array, got \(value)")
        }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0], .int(1))
        XCTAssertEqual(items[1], .double(2.5))
        XCTAssertEqual(items[2], .string("x"))
        XCTAssertEqual(items[3], .bool(true))
        XCTAssertEqual(items[4], .null)
    }

    func test_jsonValue_decodesTopLevelScalar() throws {
        let n = try decodeJSONValue("42")
        XCTAssertEqual(n, .int(42))
        let s = try decodeJSONValue(#""hi""#)
        XCTAssertEqual(s, .string("hi"))
    }

    func test_formatJSON_serializesObject() throws {
        let value = try decodeJSONValue(#"{"a":1,"b":"x"}"#)
        let formatted = DisplayRowBuilder.formatJSON(value)
        // Key order isn't guaranteed by JSONSerialization, so re-decode and compare.
        let reparsed = try JSONSerialization.jsonObject(with: Data((formatted ?? "").utf8))
        XCTAssertEqual(reparsed as? [String: AnyHashable], ["a": 1, "b": "x"])
    }

    func test_formatJSON_serializesTopLevelScalar() {
        XCTAssertEqual(DisplayRowBuilder.formatJSON(.int(42)), "42")
        XCTAssertEqual(DisplayRowBuilder.formatJSON(.string("hi")), "\"hi\"")
        XCTAssertEqual(DisplayRowBuilder.formatJSON(.null), "null")
    }

    func test_timestampDisplayMode_currentDefaultsToMixedWhenAbsent() {
        // Snapshot any existing value to avoid leaking between runs.
        let key = TimestampDisplayMode.storageKey
        let prior = UserDefaults.standard.string(forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(TimestampDisplayMode.current, .mixed)

        UserDefaults.standard.set("garbage", forKey: key)
        XCTAssertEqual(TimestampDisplayMode.current, .mixed, "unknown raw value should fall back to .mixed")

        UserDefaults.standard.set(TimestampDisplayMode.utc.rawValue, forKey: key)
        XCTAssertEqual(TimestampDisplayMode.current, .utc)
    }
}
