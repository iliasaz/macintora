import Foundation
import OracleNIO

/// Typed value for a named bind variable coming from the `BindVarInputView`.
///
/// Each case encodes the user-provided typed value; `.null` represents explicit NULL.
/// Matches the previous SwiftOracle BindVar semantics that the UI grew around.
nonisolated enum BindValue: Hashable, Sendable {
    case text(String)
    case int(Int)
    case decimal(Double)
    case date(Date)
    case null
}

extension BindValue {
    /// Build an ``OracleStatement`` by pairing the user's SQL (with `:name` placeholders
    /// preserved) with an ``OracleBindings`` whose members are named to match.
    ///
    /// Bind names in the ``binds`` dictionary may include or omit the leading `:`.
    static func makeStatement(
        sql: String,
        binds: [String: BindValue]
    ) -> OracleStatement {
        var bindings = OracleBindings(capacity: binds.count)
        for (rawName, value) in binds {
            let name = rawName.hasPrefix(":") ? String(rawName.dropFirst()) : rawName
            value.appendTo(&bindings, bindName: name)
        }
        return OracleStatement(unsafeSQL: sql, binds: bindings)
    }

    fileprivate func appendTo(_ bindings: inout OracleBindings, bindName: String) {
        switch self {
        case .text(let s):
            bindings.append(s, context: .default, bindName: bindName)
        case .int(let i):
            bindings.append(i, context: .default, bindName: bindName)
        case .decimal(let d):
            bindings.append(OracleNumber(d), context: .default, bindName: bindName)
        case .date(let d):
            bindings.append(d, context: .default, bindName: bindName)
        case .null:
            bindings.appendNull(.varchar, bindName: bindName)
        }
    }
}
