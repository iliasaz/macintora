import Foundation
import OracleNIO
import NIOCore

/// User-controlled policy for rendering DATE / TIMESTAMP-family values in result grids.
///
/// Persisted in `UserDefaults` under ``TimestampDisplayMode/storageKey``; rendered via
/// ``DisplayRowBuilder/formatDate(_:type:mode:)``. Callers normally read the current
/// value via ``TimestampDisplayMode/current``.
nonisolated enum TimestampDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// Render every value in UTC. Useful when comparing against tools that always
    /// normalize to UTC.
    case utc
    /// Render every value in the user's local timezone. TZ-aware values are converted;
    /// non-TZ values visibly shift by the user's offset (because oracle-nio interprets
    /// DATE/TIMESTAMP wire components as UTC instants).
    case local
    /// Render TZ-aware values in the user's local timezone, and DATE/TIMESTAMP values
    /// as their raw stored components (matches what SQL Developer shows for DATE).
    case mixed

    static let storageKey = "timestampDisplayMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .utc: "Always UTC"
        case .local: "Always local time"
        case .mixed: "Local for TZ-aware, DB time otherwise"
        }
    }

    /// Reads the current setting from `UserDefaults`. Falls back to ``mixed`` when no
    /// value has been written yet.
    static var current: TimestampDisplayMode {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let mode = TimestampDisplayMode(rawValue: raw)
        else { return .mixed }
        return mode
    }
}

/// A single rendered cell owned by ``DisplayRow``.
nonisolated struct DisplayField: Hashable, Sendable {
    let name: String
    let valueString: String
    let sortKey: DisplayRow.SortKey

    /// Compatibility shim matching SwiftOracle's `SwiftyField.int`: returns the cell's
    /// numeric value if its sort key is a number.
    var int: Int? {
        if case let .number(d) = sortKey { return Int(d) }
        return Int(valueString)
    }

    var double: Double? {
        if case let .number(d) = sortKey { return d }
        return Double(valueString)
    }

    var string: String? {
        valueString.isEmpty && sortKey == .null ? nil : valueString
    }

    var date: Date? {
        if case let .date(d) = sortKey { return d }
        return nil
    }

    var isNull: Bool { sortKey == .null }
}

/// A row rendered for display in the result table.
///
/// Owns its column labels and per-column stringified values so SwiftUI/NSTableView code
/// never touches oracle-nio types directly. Sort keys are preserved for type-aware sorting.
nonisolated struct DisplayRow: Hashable, Sendable, Identifiable {
    let id: Int
    let fields: [DisplayField]

    var values: [String] { fields.map(\.valueString) }
    var sortKeys: [SortKey] { fields.map(\.sortKey) }

    subscript(columnName: String) -> DisplayField? {
        fields.first { $0.name == columnName }
    }

    subscript(columnIndex: Int) -> DisplayField? {
        guard fields.indices.contains(columnIndex) else { return nil }
        return fields[columnIndex]
    }

    enum SortKey: Hashable, Sendable, Comparable {
        case number(Double)
        case date(Date)
        case text(String)
        case null

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            switch (lhs, rhs) {
            case (.null, .null): return false
            case (.null, _): return true
            case (_, .null): return false
            case (.number(let a), .number(let b)): return a < b
            case (.date(let a), .date(let b)): return a < b
            case (.text(let a), .text(let b)): return a.localizedStandardCompare(b) == .orderedAscending
            default:
                return String(describing: lhs) < String(describing: rhs)
            }
        }
    }

    static func less(colIndex: Int, lhs: DisplayRow, rhs: DisplayRow) -> Bool {
        let left = lhs.fields.indices.contains(colIndex) ? lhs.fields[colIndex].sortKey : .null
        let right = rhs.fields.indices.contains(colIndex) ? rhs.fields[colIndex].sortKey : .null
        return left < right
    }
}

/// Renders an ``OracleRow`` into a ``DisplayRow``.
nonisolated enum DisplayRowBuilder {
    static let nullPlaceholder = "(null)"

    static func make(from row: OracleRow, id: Int, columnLabels: [String]) -> DisplayRow {
        let mode = TimestampDisplayMode.current
        var fields: [DisplayField] = []
        var index = 0
        for cell in row {
            let (string, key) = render(cell: cell, mode: mode)
            let name = columnLabels.indices.contains(index) ? columnLabels[index] : cell.columnName
            fields.append(DisplayField(name: name, valueString: string, sortKey: key))
            index += 1
        }
        return DisplayRow(id: id, fields: fields)
    }

    static func columnLabels(for columns: OracleColumns) -> [String] {
        columns.map { $0.name }
    }

    private static func render(cell: OracleCell, mode: TimestampDisplayMode) -> (String, DisplayRow.SortKey) {
        guard cell.bytes != nil else {
            return (nullPlaceholder, .null)
        }
        let type = cell.dataType
        switch type {
        case .number, .binaryDouble, .binaryFloat, .binaryInteger:
            if let value = try? cell.decode(Double.self) {
                return (formatNumber(value), .number(value))
            }
        case .date, .timestamp, .timestampLTZ, .timestampTZ:
            if let date = try? cell.decode(Date.self) {
                let hasTimeZone = (type == .timestampTZ || type == .timestampLTZ)
                return (formatDate(date, hasTimeZone: hasTimeZone, mode: mode), .date(date))
            }
        case .boolean:
            if let value = try? cell.decode(Bool.self) {
                let s = value ? "true" : "false"
                return (s, .text(s))
            }
        case .json:
            if let json = try? cell.decode(OracleJSON<JSONValue>.self),
               let s = formatJSON(json.value) {
                return (s, .text(s))
            }
        default:
            break
        }
        if let s = try? cell.decode(String.self) {
            return (s, .text(s))
        }
        // Fall back to a hex dump for binary types (RAW, BLOB, etc.): cap at 32 bytes to keep the display readable.
        if let bytes = cell.bytes {
            let hex = bytes.readableBytesView.prefix(32).map { byte in
                let s = String(byte, radix: 16, uppercase: false)
                return s.count < 2 ? "0\(s)" : s
            }.joined()
            return (hex, .text(hex))
        }
        return (nullPlaceholder, .null)
    }

    /// Schema-less decode target for Oracle `JSON` columns. Mirrors the JSON spec:
    /// every value is null, bool, integer, double, string, array, or object.
    /// Bridged to `Any` for `JSONSerialization` so we can render the original column
    /// text without knowing the column's Codable shape.
    @usableFromInline
    enum JSONValue: Decodable, Sendable, Equatable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        @usableFromInline
        init(from decoder: any Decoder) throws {
            // Try keyed first so { "key": ... } objects don't get misclassified as
            // single values. Fall through to unkeyed (arrays) and finally scalars.
            if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
                var dict: [String: JSONValue] = [:]
                for key in keyed.allKeys {
                    dict[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
                }
                self = .object(dict)
                return
            }
            if var unkeyed = try? decoder.unkeyedContainer() {
                var arr: [JSONValue] = []
                if let count = unkeyed.count { arr.reserveCapacity(count) }
                while !unkeyed.isAtEnd {
                    arr.append(try unkeyed.decode(JSONValue.self))
                }
                self = .array(arr)
                return
            }
            let single = try decoder.singleValueContainer()
            if single.decodeNil() { self = .null; return }
            if let v = try? single.decode(Bool.self) { self = .bool(v); return }
            if let v = try? single.decode(Int64.self) { self = .int(v); return }
            if let v = try? single.decode(Double.self) { self = .double(v); return }
            if let v = try? single.decode(String.self) { self = .string(v); return }
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Unsupported JSON scalar"
            )
        }

        /// `Any`-bridged form for `JSONSerialization`. Uses `NSNull` for null because
        /// `JSONSerialization` rejects Swift's `Optional<Any>.none`.
        var anyValue: Any {
            switch self {
            case .null: NSNull()
            case .bool(let v): v
            case .int(let v): v
            case .double(let v): v
            case .string(let v): v
            case .array(let arr): arr.map(\.anyValue)
            case .object(let dict): dict.mapValues(\.anyValue)
            }
        }
    }

    /// CodingKey shim so we can iterate object keys when decoding a `JSONValue` from
    /// oracle-nio's keyed container without knowing the schema.
    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue) }
    }

    static func formatJSON(_ value: JSONValue) -> String? {
        // Top-level scalars aren't valid input for `JSONSerialization` until macOS 13's
        // `.fragmentsAllowed`; pass it explicitly so a JSON column holding e.g. just
        // `42` or `"hi"` still renders.
        guard let data = try? JSONSerialization.data(
            withJSONObject: value.anyValue,
            options: [.fragmentsAllowed]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func formatNumber(_ d: Double) -> String {
        if d.truncatingRemainder(dividingBy: 1) == 0, abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }

    /// Safety invariant for `nonisolated(unsafe)`: `ISO8601DateFormatter` is not
    /// `Sendable`, but Apple documents it as thread-safe for read-only use once
    /// configured. These formatters are immutable after init and only ever call
    /// `.string(from:)` — safe to share across isolations.
    private nonisolated(unsafe) static let utcFormatter: ISO8601DateFormatter =
        makeFormatter(timeZone: TimeZone(secondsFromGMT: 0)!, includeOffset: false)
    private nonisolated(unsafe) static let utcFormatterWithOffset: ISO8601DateFormatter =
        makeFormatter(timeZone: TimeZone(secondsFromGMT: 0)!, includeOffset: true)
    private nonisolated(unsafe) static let localFormatterWithOffset: ISO8601DateFormatter =
        makeFormatter(timeZone: .current, includeOffset: true)

    private static func makeFormatter(timeZone: TimeZone, includeOffset: Bool) -> ISO8601DateFormatter {
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

    /// Renders a decoded date value according to the user's display-mode preference.
    ///
    /// - Parameter hasTimeZone: `true` for TIMESTAMP WITH TIME ZONE / TIMESTAMP WITH
    ///   LOCAL TIME ZONE columns; `false` for plain DATE / TIMESTAMP. Used only to
    ///   resolve the `.mixed` policy.
    ///
    /// - For `.utc` mode: always UTC, with offset shown.
    /// - For `.local` mode: always local timezone, with offset shown.
    /// - For `.mixed` mode: TZ-aware values render in local timezone (with offset);
    ///   plain DATE/TIMESTAMP values render as their raw stored components
    ///   (UTC-formatted, no offset — because oracle-nio decodes those wire bytes as
    ///   UTC instants, so UTC-formatting reproduces the original column values).
    static func formatDate(_ d: Date, hasTimeZone: Bool, mode: TimestampDisplayMode) -> String {
        let formatter: ISO8601DateFormatter
        switch (mode, hasTimeZone) {
        case (.utc, _):
            formatter = unsafe utcFormatterWithOffset
        case (.local, _):
            formatter = unsafe localFormatterWithOffset
        case (.mixed, true):
            formatter = unsafe localFormatterWithOffset
        case (.mixed, false):
            formatter = unsafe utcFormatter
        }
        return formatter.string(from: d)
    }
}
