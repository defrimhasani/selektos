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
        let clock = ContinuousClock()
        let start = clock.now
        let data = try await runCommand(sql, connection: connection)
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
        let tableResult = try await execute(
            sql: """
            SELECT name
            FROM sqlite_schema
            WHERE type IN ('table', 'view')
              AND name NOT LIKE 'sqlite_%'
              AND name NOT GLOB '_cf_*'
            ORDER BY name;
            """,
            connection: connection,
            maximumRows: .max
        )
        let tableNames = tableResult.rows.compactMap(\.values.first).filter { !$0.isEmpty }
        guard !tableNames.isEmpty else {
            return [DatabaseSchema(name: "main", tables: [])]
        }

        let data = try await runCommand(
            schemaMetadataCommand(for: tableNames),
            connection: connection
        )
        return try decodeSchema(tableNames: tableNames, from: data)
    }

    func schemaMetadataCommand(for tableNames: [String]) -> String {
        tableNames
            .map { "PRAGMA table_info(\(sqlStringLiteral($0)));" }
            .joined(separator: "\n")
    }

    func decodeSchema(tableNames: [String], from data: Data) throws -> [DatabaseSchema] {
        let batches = try decodeBatches(data)
        guard batches.count == tableNames.count else {
            throw D1Error.message(
                "Wrangler returned metadata for \(batches.count) of \(tableNames.count) D1 tables."
            )
        }

        let tables = zip(tableNames, batches).map { tableName, batch in
            let columns = batch.results
                .sorted { (number($0["cid"]) ?? 0) < (number($1["cid"]) ?? 0) }
                .compactMap { object -> DatabaseColumn? in
                    guard let name = string(object["name"]) else { return nil }
                    let dataType = string(object["type"]) ?? ""
                    return DatabaseColumn(
                        name: name,
                        dataType: dataType.isEmpty ? "ANY" : dataType,
                        isNullable: (number(object["notnull"]) ?? 0) == 0,
                        isPrimaryKey: (number(object["pk"]) ?? 0) != 0
                    )
                }
            return DatabaseTable(schema: "main", name: tableName, columns: columns)
        }
        return [DatabaseSchema(name: "main", tables: tables)]
    }

    private func runCommand(_ sql: String, connection: DatabaseConnection) async throws -> Data {
        let database = connection.d1Database ?? connection.database
        guard !database.isEmpty else { throw D1Error.message("Choose a D1 database.") }
        var arguments = ["d1", "execute", database, "--remote", "--command", sql, "--json", "--yes"]
        appendProfile(connection.wranglerProfile ?? "", to: &arguments)
        return try await WranglerProcess.run(
            path: connection.wranglerPath ?? "wrangler",
            arguments: arguments
        )
    }

    private func sqlStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func string(_ value: JSONValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private func number(_ value: JSONValue?) -> Double? {
        guard case .number(let number) = value else { return nil }
        return number
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

enum WranglerErrorFormatter {
    static func message(from data: Data) -> String {
        if let response = try? JSONDecoder().decode(WranglerErrorResponse.self, from: data) {
            return ([response.error.text] + response.error.notes.map(\.text))
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        guard let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return "Wrangler failed."
        }
        return message
    }
}

private struct WranglerErrorResponse: Decodable {
    let error: WranglerErrorDetail
}

private struct WranglerErrorDetail: Decodable {
    let text: String
    let notes: [WranglerErrorNote]
}

private struct WranglerErrorNote: Decodable {
    let text: String
}

struct WranglerExecutableResolver {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL
    private let standardSearchDirectories: [URL]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        standardSearchDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.standardSearchDirectories = standardSearchDirectories ?? [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".asdf/shims", isDirectory: true)
        ]
    }

    func resolve(_ configuredPath: String) throws -> URL {
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw D1Error.message("Enter a Wrangler executable path.")
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        if expandedPath.contains("/") {
            guard fileManager.isExecutableFile(atPath: expandedPath) else {
                throw D1Error.message("Wrangler is not executable at \(expandedPath).")
            }
            return URL(fileURLWithPath: expandedPath)
        }

        for directory in searchDirectories() {
            let candidate = directory.appendingPathComponent(expandedPath)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw D1Error.message("Wrangler was not found. Install it globally or enter its full executable path in the D1 connection.")
    }

    func processEnvironment(for executable: URL) -> [String: String] {
        var processEnvironment = environment
        let systemDirectories = [
            URL(fileURLWithPath: "/usr/bin", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/sbin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true)
        ]
        let directories = uniqueDirectories(
            [executable.deletingLastPathComponent()]
                + pathDirectories()
                + standardSearchDirectories
                + systemDirectories
        )
        processEnvironment["PATH"] = directories.map(\.path).joined(separator: ":")
        processEnvironment["NO_COLOR"] = "1"
        return processEnvironment
    }

    private func searchDirectories() -> [URL] {
        uniqueDirectories(pathDirectories() + standardSearchDirectories + nvmSearchDirectories())
    }

    private func pathDirectories() -> [URL] {
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return path.split(separator: ":").map {
            URL(
                fileURLWithPath: NSString(string: String($0)).expandingTildeInPath,
                isDirectory: true
            )
        }
    }

    private func nvmSearchDirectories() -> [URL] {
        var directories: [URL] = []
        if let nvmBin = environment["NVM_BIN"], !nvmBin.isEmpty {
            directories.append(
                URL(
                    fileURLWithPath: NSString(string: nvmBin).expandingTildeInPath,
                    isDirectory: true
                )
            )
        }

        let nvmDirectory: URL
        if let configuredNVMDirectory = environment["NVM_DIR"], !configuredNVMDirectory.isEmpty {
            nvmDirectory = URL(
                fileURLWithPath: NSString(string: configuredNVMDirectory).expandingTildeInPath,
                isDirectory: true
            )
        } else {
            nvmDirectory = homeDirectory.appendingPathComponent(".nvm", isDirectory: true)
        }

        let versionsDirectory = nvmDirectory.appendingPathComponent("versions/node", isDirectory: true)
        guard let versions = try? fileManager.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return directories
        }

        let versionDirectories = versions
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted {
                $0.lastPathComponent.compare(
                    $1.lastPathComponent,
                    options: [.numeric, .caseInsensitive]
                ) == .orderedDescending
            }
            .map { $0.appendingPathComponent("bin", isDirectory: true) }
        return directories + versionDirectories
    }

    private func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        return directories.compactMap { directory in
            let standardized = directory.standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }
}

private enum WranglerProcess {
    static func run(path: String, arguments: [String]) async throws -> Data {
        let resolver = WranglerExecutableResolver()
        let executable = try resolver.resolve(path)
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.environment = resolver.processEnvironment(for: executable)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    let stdout = output.fileHandleForReading.readDataToEndOfFile()
                    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: stdout)
                    } else {
                        let failureOutput = stderr.isEmpty ? stdout : stderr
                        continuation.resume(
                            throwing: D1Error.message(WranglerErrorFormatter.message(from: failureOutput))
                        )
                    }
                }
                do { try process.run() }
                catch { continuation.resume(throwing: D1Error.message("Could not launch Wrangler at \(executable.path): \(error.localizedDescription)")) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
