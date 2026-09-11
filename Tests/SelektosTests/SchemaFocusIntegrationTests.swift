import Foundation
import XCTest
@testable import Selektos

/// End-to-end check that a focused schema actually changes how Postgres resolves
/// unqualified names. Skipped when no local Postgres fixture is reachable.
///
/// Recreate the fixture with:
///
///     createdb qd_probe
///     psql -d qd_probe \
///       -c "CREATE SCHEMA app;" \
///       -c "CREATE TABLE app.widget(id int primary key, note text);" \
///       -c "INSERT INTO app.widget VALUES (1,'from-app-schema');" \
///       -c "CREATE TABLE public.widget(id int primary key, note text);" \
///       -c "INSERT INTO public.widget VALUES (99,'from-public');"
///
/// Remove it with `dropdb qd_probe`.
final class SchemaFocusIntegrationTests: XCTestCase {
    private let service = PostgresService()

    private var connection: DatabaseConnection {
        DatabaseConnection(
            kind: .postgresql,
            name: "probe",
            host: "localhost",
            port: 5432,
            database: "qd_probe",
            username: NSUserName(),
            tlsMode: .disable,
            labels: []
        )
    }

    private func requireFixture() async throws {
        do {
            _ = try await service.execute(
                sql: "SELECT 1 FROM app.widget LIMIT 1;",
                connection: connection,
                password: ""
            )
        } catch {
            throw XCTSkip("qd_probe fixture unavailable: \(error.localizedDescription)")
        }
    }

    func testUnfocusedQueryResolvesAgainstPublic() async throws {
        try await requireFixture()
        let result = try await service.execute(
            sql: "SELECT note FROM widget;",
            connection: connection,
            password: ""
        )
        XCTAssertEqual(result.rows.first?.values.first, "from-public")
    }

    func testFocusedSchemaResolvesUnqualifiedNamesThere() async throws {
        try await requireFixture()
        let result = try await service.execute(
            sql: "SELECT note FROM widget;",
            connection: connection,
            password: "",
            searchPath: "app"
        )
        XCTAssertEqual(result.rows.first?.values.first, "from-app-schema")
    }

    func testFocusedSchemaStillReachesPublic() async throws {
        try await requireFixture()
        let result = try await service.execute(
            sql: "SELECT count(*) FROM pg_class;",
            connection: connection,
            password: "",
            searchPath: "app"
        )
        XCTAssertNotNil(result.rows.first?.values.first)
    }

    func testFocusingAnUnknownSchemaDoesNotBreakTheConnection() async throws {
        try await requireFixture()
        let result = try await service.execute(
            sql: "SELECT 1;",
            connection: connection,
            password: "",
            searchPath: "does_not_exist"
        )
        XCTAssertEqual(result.rows.first?.values.first, "1")
    }

    func testConfigurableResultLimitIsEnforced() async throws {
        try await requireFixture()
        let result = try await service.execute(
            sql: "SELECT generate_series(1, 5);",
            connection: connection,
            password: "",
            maximumRows: 2
        )
        XCTAssertEqual(result.rows.count, 2)
    }

    /// The schema dropdown is built from `fetchSchema` minus Postgres internals.
    func testDiscoveredSchemasFeedTheFocusPicker() async throws {
        try await requireFixture()
        let discovered = try await service.fetchSchema(connection: connection, password: "")
        let names = discovered.map(\.name)

        XCTAssertTrue(names.contains("app"), "expected fixture schema, got \(names)")
        XCTAssertTrue(names.contains("pg_catalog"), "superuser should see internals before filtering")

        let offered = names.filter { !AppStore.isInternalSchema($0) }.sorted()
        XCTAssertEqual(offered, ["app", "public"])
    }
}
