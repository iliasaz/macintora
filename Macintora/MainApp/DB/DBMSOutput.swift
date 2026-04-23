import Foundation
import OracleNIO
import Logging

/// Helpers for capturing `DBMS_OUTPUT` buffered output from PL/SQL.
///
/// Because oracle-nio has no built-in DBMS_OUTPUT API, we emulate the feature by
/// enabling the server-side buffer and then calling `DBMS_OUTPUT.GET_LINE` in a loop
/// after each user statement.
nonisolated enum DBMSOutput {
    static func enable(on connection: OracleConnection, logger: Logger) async throws {
        try await connection.execute(
            "BEGIN DBMS_OUTPUT.ENABLE(NULL); END;",
            logger: logger
        )
    }

    static func disable(on connection: OracleConnection, logger: Logger) async throws {
        try await connection.execute(
            "BEGIN DBMS_OUTPUT.DISABLE; END;",
            logger: logger
        )
    }

    /// Drains the DBMS_OUTPUT buffer into a single newline-joined string.
    ///
    /// We cap at 10_000 lines per drain to guard against unbounded PUT_LINE loops.
    static func drain(on connection: OracleConnection, logger: Logger) async throws -> String {
        var lines: [String] = []
        let maxLines = 10_000
        for _ in 0..<maxLines {
            let lineRef = OracleRef(dataType: .varchar)
            let statusRef = OracleRef(dataType: .number)
            try await connection.execute(
                "BEGIN DBMS_OUTPUT.GET_LINE(\(lineRef), \(statusRef)); END;",
                logger: logger
            )
            let status = (try? statusRef.decode(as: Int.self)) ?? 1
            if status != 0 { break }
            let line = (try? lineRef.decode(as: String.self)) ?? ""
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
