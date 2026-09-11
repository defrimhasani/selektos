import Foundation
import PostgresNIO

struct PostgresService: Sendable {
    func execute(
        sql: String,
        connection: DatabaseConnection,
        password: String,
        searchPath: String? = nil,
        maximumRows: Int = 10_000
    ) async throws -> QueryResult {
        let clock = ContinuousClock()
        let start = clock.now
        let client = makeClient(connection: connection, password: password, searchPath: searchPath)
        let runTask = Task { await client.run() }
        defer { runTask.cancel() }

        try Task.checkCancellation()
        let sequence = try await client.query(PostgresQuery(unsafeSQL: sql))
        let columns = sequence.columns.map(\.name)
        var rows: [QueryResultRow] = []
        rows.reserveCapacity(min(maximumRows, 500))

        for try await row in sequence {
            try Task.checkCancellation()
            guard rows.count < maximumRows else { continue }
            rows.append(QueryResultRow(id: rows.count, values: row.map(displayValue)))
        }

        return QueryResult(
            columns: columns,
            rows: rows,
            command: commandName(from: sql),
            duration: start.duration(to: clock.now)
        )
    }

    func fetchSchema(connection: DatabaseConnection, password: String) async throws -> [DatabaseSchema] {
        let sql = """
        WITH primary_keys AS (
            SELECT kcu.table_schema, kcu.table_name, kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON kcu.constraint_name = tc.constraint_name
             AND kcu.constraint_schema = tc.constraint_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
        )
        SELECT
            s.schema_name,
            t.table_name,
            c.column_name,
            c.data_type,
            c.is_nullable,
            CASE WHEN pk.column_name IS NOT NULL THEN 'true' ELSE 'false' END AS is_primary_key
        FROM information_schema.schemata s
        LEFT JOIN information_schema.tables t
          ON t.table_schema = s.schema_name
         AND t.table_type IN ('BASE TABLE', 'VIEW', 'FOREIGN')
        LEFT JOIN information_schema.columns c
          ON c.table_schema = t.table_schema
         AND c.table_name = t.table_name
        LEFT JOIN primary_keys pk
          ON pk.table_schema = c.table_schema
         AND pk.table_name = c.table_name
         AND pk.column_name = c.column_name
        ORDER BY s.schema_name, t.table_name, c.ordinal_position
        """
        let result = try await execute(
            sql: sql,
            connection: connection,
            password: password,
            maximumRows: .max
        )
        let grouped = Dictionary(grouping: result.rows) { $0.values.first ?? "public" }
        return grouped.keys.sorted().map { schema in
            let tableRows = Dictionary(grouping: grouped[schema, default: []]) { row in
                guard row.values.count > 1, row.values[1] != "NULL" else { return "" }
                return row.values[1]
            }
            return DatabaseSchema(
                name: schema,
                tables: tableRows.keys.filter { !$0.isEmpty }.sorted().map { tableName in
                    let columns = tableRows[tableName, default: []].compactMap { row -> DatabaseColumn? in
                        guard row.values.count > 5, row.values[2] != "NULL" else { return nil }
                        return DatabaseColumn(
                            name: row.values[2],
                            dataType: row.values[3],
                            isNullable: row.values[4] == "YES",
                            isPrimaryKey: row.values[5] == "true"
                        )
                    }
                    return DatabaseTable(schema: schema, name: tableName, columns: columns)
                }
            )
        }
    }

    func fetchDatabases(connection: DatabaseConnection, password: String) async throws -> [String] {
        let result = try await execute(
            sql: "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname;",
            connection: connection,
            password: password,
            maximumRows: .max
        )
        return result.rows.compactMap(\.values.first)
    }

    private func makeClient(
        connection: DatabaseConnection,
        password: String,
        searchPath: String? = nil
    ) -> PostgresClient {
        let tls: PostgresClient.Configuration.TLS
        switch connection.tlsMode {
        case .disable:
            tls = .disable
        case .prefer:
            tls = .prefer(.makeClientConfiguration())
        case .require:
            tls = .require(.makeClientConfiguration())
        }
        var configuration = PostgresClient.Configuration(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password.isEmpty ? nil : password,
            database: connection.database,
            tls: tls
        )
        if let value = Self.searchPathValue(for: searchPath) {
            configuration.options.additionalStartupParameters = [("search_path", value)]
        }
        return PostgresClient(configuration: configuration)
    }

    /// Builds a `search_path` value that resolves unqualified names in the focused
    /// schema first while keeping `public` reachable. Returns `nil` when no schema
    /// is focused, which leaves the server default untouched.
    static func searchPathValue(for schema: String?) -> String? {
        guard let schema else { return nil }
        let trimmed = schema.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let quoted = "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
        return trimmed == "public" ? quoted : "\(quoted), \"public\""
    }

    private func displayValue(_ cell: PostgresCell) -> String {
        guard cell.bytes != nil else { return "NULL" }
        do {
            switch cell.dataType {
            case .bool: return try cell.decode(Bool.self) ? "true" : "false"
            case .int2: return String(try cell.decode(Int16.self))
            case .int4: return String(try cell.decode(Int32.self))
            case .int8: return String(try cell.decode(Int64.self))
            case .float4: return String(try cell.decode(Float.self))
            case .float8: return String(try cell.decode(Double.self))
            case .numeric: return String(describing: try cell.decode(Decimal.self))
            case .uuid: return try cell.decode(UUID.self).uuidString
            case .timestamp, .timestamptz, .date:
                return ISO8601DateFormatter().string(from: try cell.decode(Date.self))
            case .varchar, .bpchar, .text, .name, .json, .jsonb, .xml:
                return try cell.decode(String.self)
            case .bytea:
                return "\\x" + (try cell.decode(ByteBuffer.self)).readableBytesView.map { String(format: "%02x", $0) }.joined()
            default:
                return rawValue(cell)
            }
        } catch {
            return rawValue(cell)
        }
    }

    private func rawValue(_ cell: PostgresCell) -> String {
        guard let bytes = cell.bytes else { return "NULL" }
        let raw = Array(bytes.readableBytesView)
        if let string = String(bytes: raw, encoding: .utf8), !string.contains("\0") { return string }
        return "\\x" + raw.map { String(format: "%02x", $0) }.joined()
    }

    private func commandName(from sql: String) -> String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0 == ";" })
            .first.map { String($0).uppercased() } ?? "QUERY"
    }
}
