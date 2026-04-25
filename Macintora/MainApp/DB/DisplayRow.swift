import Foundation
import OracleNIO
import NIOCore

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
        var fields: [DisplayField] = []
        var index = 0
        for cell in row {
            let (string, key) = render(cell: cell)
            let name = columnLabels.indices.contains(index) ? columnLabels[index] : cell.columnName
            fields.append(DisplayField(name: name, valueString: string, sortKey: key))
            index += 1
        }
        return DisplayRow(id: id, fields: fields)
    }

    static func columnLabels(for columns: OracleColumns) -> [String] {
        columns.map { $0.name }
    }

    private static func render(cell: OracleCell) -> (String, DisplayRow.SortKey) {
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
                return (formatDate(date), .date(date))
            }
        case .boolean:
            if let value = try? cell.decode(Bool.self) {
                let s = value ? "true" : "false"
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

    private static func formatNumber(_ d: Double) -> String {
        if d.truncatingRemainder(dividingBy: 1) == 0, abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }

    /// Safety invariant for `nonisolated(unsafe)`: `ISO8601DateFormatter` is not
    /// `Sendable`, but Apple documents it as thread-safe for read-only use once
    /// configured. This formatter is immutable after init and only ever calls
    /// `.string(from:)` — safe to share across isolations.
    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [
            .withFullDate, .withTime,
            .withDashSeparatorInDate, .withColonSeparatorInTime,
            .withSpaceBetweenDateAndTime
        ]
        return f
    }()

    private static func formatDate(_ d: Date) -> String {
        unsafe dateFormatter.string(from: d)
    }
}
