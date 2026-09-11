import Foundation

struct D1Service: Sendable {
    func listDatabases(wranglerPath: String, profile: String) async throws -> [D1Database] {
        var arguments = ["d1", "list", "--json"]
        appendProfile(profile, to: &arguments)
        let data = try await WranglerProcess.run(path: wranglerPath, arguments: arguments)
        let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return objects.compactMap { object in
            guard let id = object["uuid"] as? String ?? object["id"] as? String,
                  let name = object["name"] as? String else { return nil }
            return D1Database(id: id, name: name)
        }
    }

    func execute(
        sql: String,
        connection: DatabaseConnection,
        maximumRows: Int = 10_000
    ) async throws -> QueryResult {
        let database = connection.d1Database ?? connection.database
        guard !database.isEmpty else { throw D1Error.message("Choose a D1 database.") }
        let clock = ContinuousClock()
        let start = clock.now
        var arguments = ["d1", "execute", database, "--remote", "--command", sql, "--json", "--yes"]
        appendProfile(connection.wranglerProfile ?? "", to: &arguments)
        let data = try await WranglerProcess.run(path: connection.wranglerPath ?? "wrangler", arguments: arguments)
        let batches = try decodeBatches(data)
        guard let batch = batches.last else {
            return QueryResult(columns: [], rows: [], command: commandName(sql), duration: start.duration(to: clock.now))
        }
        let columns = orderedColumns(from: batch.results)
        let rows = batch.results.prefix(maximumRows).enumerated().map { index, object in
            QueryResultRow(id: index, values: columns.map { display(object[$0] ?? .null) })
        }
        let duration = batch.meta?.duration.map { Duration.milliseconds(Int64($0.rounded())) }
            ?? start.duration(to: clock.now)
        return QueryResult(columns: columns, rows: rows, command: commandName(sql), duration: duration)
    }

    func fetchSchema(connection: DatabaseConnection) async throws -> [DatabaseSchema] {
        let result = try await execute(
            sql: """
            SELECT
                m.name AS a_table_name,
                p.name AS b_column_name,
                p.type AS c_data_type,
                p.[notnull] AS d_not_null,
                p.pk AS e_primary_key
            FROM sqlite_schema AS m
            JOIN pragma_table_info(m.name) AS p
            WHERE m.type IN ('table', 'view')
              AND m.name NOT LIKE 'sqlite_%'
            ORDER BY m.name, p.cid;
            """,
            connection: connection,
            maximumRows: .max
        )
        let grouped = Dictionary(grouping: result.rows) { $0.values.first ?? "" }
        let tables = grouped.keys.filter { !$0.isEmpty }.sorted().map { tableName in
            let columns = grouped[tableName, default: []].compactMap { row -> DatabaseColumn? in
                guard row.values.count > 4 else { return nil }
                return DatabaseColumn(
                    name: row.values[1],
                    dataType: row.values[2].isEmpty ? "ANY" : row.values[2],
                    isNullable: row.values[3] == "0",
                    isPrimaryKey: row.values[4] != "0"
                )
            }
            return DatabaseTable(schema: "main", name: tableName, columns: columns)
        }
        return [DatabaseSchema(name: "main", tables: tables)]
    }

    private func appendProfile(_ profile: String, to arguments: inout [String]) {
        let trimmed = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { arguments += ["--profile", trimmed] }
    }

    private func decodeBatches(_ data: Data) throws -> [D1Batch] {
        do { return try JSONDecoder().decode([D1Batch].self, from: data) }
        catch {
            if let batch = try? JSONDecoder().decode(D1Batch.self, from: data) { return [batch] }
            throw D1Error.message("Wrangler returned an unsupported JSON response: \(error.localizedDescription)")
        }
    }

    private func orderedColumns(from rows: [[String: JSONValue]]) -> [String] {
        guard let first = rows.first else { return [] }
        return Array(first.keys).sorted()
    }

    private func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return String(format: "%g", value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "NULL"
        case .array, .object:
            return (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? ""
        }
    }

    private func commandName(_ sql: String) -> String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map { $0.uppercased() } ?? "QUERY"
    }
}

private struct D1Batch: Decodable {
    let results: [[String: JSONValue]]
    let success: Bool?
    let meta: D1Meta?
}

private struct D1Meta: Decodable {
    let duration: Double?
}

private enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private enum D1Error: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

private enum WranglerProcess {
    static func run(path: String, arguments: [String]) async throws -> Data {
        let executable = try resolve(path)
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.environment = environment()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    let stdout = output.fileHandleForReading.readDataToEndOfFile()
                    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: stdout)
                    } else {
                        let message = String(data: stderr.isEmpty ? stdout : stderr, encoding: .utf8) ?? "Wrangler failed."
                        continuation.resume(throwing: D1Error.message(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
                do { try process.run() }
                catch { continuation.resume(throwing: D1Error.message("Could not launch Wrangler at \(executable.path): \(error.localizedDescription)")) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func resolve(_ configuredPath: String) throws -> URL {
        let expanded = NSString(string: configuredPath).expandingTildeInPath
        if expanded.contains("/"), FileManager.default.isExecutableFile(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        let candidates = [
            "/opt/homebrew/bin/\(expanded)", "/usr/local/bin/\(expanded)",
            "\(NSHomeDirectory())/.local/bin/\(expanded)", "\(NSHomeDirectory())/.npm-global/bin/\(expanded)"
        ]
        if let match = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: match)
        }
        throw D1Error.message("Wrangler was not found. Install it globally or enter its full executable path in the D1 connection.")
    }

    private static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }
}
