import XCTest
@testable import Macintora

final class AppDBErrorTests: XCTestCase {
    func test_passThroughAppDBError() {
        let original = AppDBError(kind: .sql, message: "oops", code: "ORA-00001")
        let wrapped = AppDBError.from(original)
        XCTAssertEqual(wrapped.kind, .sql)
        XCTAssertEqual(wrapped.message, "oops")
        XCTAssertEqual(wrapped.code, "ORA-00001")
        XCTAssertEqual(wrapped.description, "[ORA-00001] oops")
    }

    func test_cancellationErrorMapping() {
        let wrapped = AppDBError.from(CancellationError())
        XCTAssertEqual(wrapped.kind, .cancelled)
    }

    func test_otherErrorMapping() {
        struct Dummy: Error, LocalizedError {
            var errorDescription: String? { "dummy" }
        }
        let wrapped = AppDBError.from(Dummy())
        XCTAssertEqual(wrapped.kind, .other)
        XCTAssertEqual(wrapped.message, "dummy")
    }

    func test_descriptionWithoutCode() {
        let err = AppDBError(kind: .connection, message: "no connection")
        XCTAssertEqual(err.description, "no connection")
    }
}

final class BindValueTests: XCTestCase {
    func test_makeStatementSubstitutesBinds() {
        let sql = "select * from t where a = :a and b = :b"
        let stmt = BindValue.makeStatement(sql: sql, binds: [":a": .text("hello"), ":b": .int(42)])
        // OracleStatement's `sql` keeps the original `:name` placeholders (bind names)
        XCTAssertTrue(stmt.sql.contains(":a"))
        XCTAssertTrue(stmt.sql.contains(":b"))
        XCTAssertEqual(stmt.binds.count, 2)
    }

    func test_makeStatementWithNullBind() {
        let sql = "select * from t where a = :a"
        let stmt = BindValue.makeStatement(sql: sql, binds: [":a": .null])
        XCTAssertEqual(stmt.binds.count, 1)
    }
}
