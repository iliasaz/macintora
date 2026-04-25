import Foundation
import OracleNIO

/// Unified error surface for all database operations in Macintora.
///
/// View models only ever catch and display ``AppDBError`` so that driver-specific error
/// types do not leak into the UI layer.
nonisolated struct AppDBError: Error, LocalizedError, Sendable, CustomStringConvertible {
    enum Kind: Sendable {
        case connection
        case sql
        case decoding
        case cancelled
        case other
    }

    let kind: Kind
    let message: String
    let code: String?

    init(kind: Kind, message: String, code: String? = nil) {
        self.kind = kind
        self.message = message
        self.code = code
    }

    var errorDescription: String? { description }

    var description: String {
        if let code {
            return "[\(code)] \(message)"
        }
        return message
    }

    // MARK: - Mapping

    static func from(_ error: any Error) -> AppDBError {
        if let app = error as? AppDBError {
            return app
        }
        if let sqlError = error as? OracleSQLError {
            let code = sqlError.serverInfo.map {
                "ORA-\($0.number.formatted(.number.precision(.integerLength(5)).grouping(.never)))"
            }
            let message = sqlError.serverInfo?.message ?? String(describing: sqlError.code)
            return AppDBError(kind: .sql, message: message, code: code)
        }
        if error is OracleDecodingError {
            return AppDBError(kind: .decoding, message: String(describing: error))
        }
        if let endpoint = error as? OracleEndpoint.ResolveError {
            return AppDBError(kind: .connection, message: endpoint.localizedDescription)
        }
        if error is CancellationError {
            return AppDBError(kind: .cancelled, message: "Operation cancelled")
        }
        return AppDBError(kind: .other, message: error.localizedDescription)
    }
}
