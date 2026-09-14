import XCTest
@testable import Selektos

final class ReadOnlySQLValidatorTests: XCTestCase {
    func testAllowsSelectStyleQueries() throws {
        let queries = [
            "SELECT id, name FROM users ORDER BY id;",
            "SELECT comment, start, copy, load FROM events;",
            "/* metadata */ WITH active AS (SELECT * FROM users WHERE active) SELECT * FROM active;",
            "VALUES (1), (2), (3);",
            "TABLE public.users;",
            "SHOW server_version;",
            "SELECT 'DELETE FROM users' AS warning, \"UPDATE\" AS quoted_identifier;",
            "SELECT \"dblink_exec\" FROM audit_log;",
            "SELECT $$DROP TABLE users$$ AS example;",
            "SELECT $message$DELETE FROM users$message$ AS example;"
        ]

        for query in queries {
            XCTAssertNoThrow(
                try ReadOnlySQLValidator.validate(query, dialect: .postgresql),
                query
            )
        }
    }

    func testAllowsSQLiteMetadataPragmas() throws {
        let queries = [
            "PRAGMA table_info('users');",
            "PRAGMA main.table_xinfo(\"users\");",
            "PRAGMA database_list;",
            "PRAGMA index_list('users');"
        ]

        for query in queries {
            XCTAssertNoThrow(
                try ReadOnlySQLValidator.validate(query, dialect: .sqlite),
                query
            )
        }
    }

    func testRejectsMutatingAndAdministrativeQueries() {
        let queries = [
            "INSERT INTO users(name) VALUES ('Ada');",
            "UPDATE users SET active = false;",
            "DELETE FROM users;",
            "WITH removed AS (DELETE FROM users RETURNING *) SELECT * FROM removed;",
            "SELECT * INTO users_backup FROM users;",
            "EXPLAIN ANALYZE DELETE FROM users;",
            "SELECT nextval('users_id_seq');",
            "SELECT pg_notify('events', 'changed');",
            "SELECT pg_terminate_backend(123);",
            "SELECT \"dblink_exec\"('remote', 'DELETE FROM users');",
            "ATTACH DATABASE 'other.db' AS other;",
            "SELECT 1; DROP TABLE users;",
            "SELECT 1 /* outer /* inner */; DELETE FROM users; */"
        ]

        for query in queries {
            XCTAssertThrowsError(
                try ReadOnlySQLValidator.validate(query, dialect: .postgresql),
                query
            )
        }
    }

    func testRejectsWritablePragmas() {
        let queries = [
            "PRAGMA writable_schema = ON;",
            "PRAGMA foreign_keys = OFF;",
            "PRAGMA journal_mode(WAL);",
            "PRAGMA user_version;"
        ]

        for query in queries {
            XCTAssertThrowsError(
                try ReadOnlySQLValidator.validate(query, dialect: .sqlite),
                query
            )
        }
    }

    func testRejectsEmptyOrMalformedSQL() {
        let queries = [
            "  -- nothing to execute",
            "SELECT 'unterminated",
            "SELECT $$unterminated",
            "/* unterminated"
        ]

        for query in queries {
            XCTAssertThrowsError(
                try ReadOnlySQLValidator.validate(query, dialect: .postgresql),
                query
            )
        }
    }

    func testSQLiteDoesNotTreatPostgresDollarQuotesAsStrings() {
        XCTAssertThrowsError(
            try ReadOnlySQLValidator.validate(
                "SELECT $$safe$$; DELETE FROM users;",
                dialect: .sqlite
            )
        )
    }
}
