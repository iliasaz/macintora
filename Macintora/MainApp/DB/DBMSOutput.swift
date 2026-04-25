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
        let stream = try await connection.execute(
            "BEGIN DBMS_OUTPUT.ENABLE(NULL); END;",
            logger: logger
        )
        // oracle-nio 1.0.0-rc.4: a PL/SQL block returns an empty OracleRowSequence
        // but the stream's server-side cleanup is driven by iterator deinit via
        // `didTerminate`, which runs asynchronously on the event loop. If the
        // caller issues another `execute(…)` before that cleanup settles the
        // state machine crashes with "readyForStatement received when statement
        // is still being executed". Explicitly draining here is synchronous
        // w.r.t. the Swift await, so subsequent executes are safe.
        for try await _ in stream { }
    }

    static func disable(on connection: OracleConnection, logger: Logger) async throws {
        let stream = try await connection.execute(
            "BEGIN DBMS_OUTPUT.DISABLE; END;",
            logger: logger
        )
        for try await _ in stream { }
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
            let stream = try await connection.execute(
                "BEGIN DBMS_OUTPUT.GET_LINE(\(lineRef), \(statusRef)); END;",
                logger: logger
            )
            for try await _ in stream { }
            let status = (try? statusRef.decode(as: Int.self)) ?? 1
            if status != 0 { break }
            let line = (try? lineRef.decode(as: String.self)) ?? ""
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
