import Foundation
import MCP

struct MCPQueryRequest: Sendable {
    let connection: DatabaseConnection
    let sql: String
    let schema: String?
    let maximumRows: Int
    let readOnly: Bool
}

protocol MCPQueryExecuting: Sendable {
    func execute(_ request: MCPQueryRequest) async throws -> QueryResult
}

struct MCPDatabaseQueryExecutor: MCPQueryExecuting {
    private let postgres = PostgresService()
    private let d1 = D1Service()

    func execute(_ request: MCPQueryRequest) async throws -> QueryResult {
        if request.readOnly {
            try ReadOnlySQLValidator.validate(
                request.sql,
                dialect: request.connection.connectionKind == .postgresql
                    ? .postgresql
                    : .sqlite
            )
        }

        switch request.connection.connectionKind {
        case .postgresql:
            let password = try KeychainStore.password(for: request.connection.id) ?? ""
            return try await postgres.execute(
                sql: request.sql,
                connection: request.connection,
                password: password,
                searchPath: request.schema,
                maximumRows: request.maximumRows,
                readOnly: request.readOnly
            )
        case .cloudflareD1:
            return try await d1.execute(
                sql: request.sql,
                connection: request.connection,
                maximumRows: request.maximumRows
            )
        }
    }
}

actor MCPToolService {
    static let listConnectionsToolName = "list_connections"

    private let persistence: AppStatePersistence
    private let settingsProvider: @Sendable () -> MCPSettings
    private let queryExecutor: any MCPQueryExecuting

    init(
        persistence: AppStatePersistence = AppStatePersistence(),
        settingsProvider: @escaping @Sendable () -> MCPSettings = { MCPPreferences.current },
        queryExecutor: any MCPQueryExecuting = MCPDatabaseQueryExecutor()
    ) {
        self.persistence = persistence
        self.settingsProvider = settingsProvider
        self.queryExecutor = queryExecutor
    }

    func listTools() throws -> ListTools.Result {
        let settings = settingsProvider()
        guard settings.isEnabled else {
            throw MCPServiceError.disabled
        }
        let connections = try connectionReferences()
        let tools = [Self.listConnectionsTool()] + connections.flatMap {
            [
                Self.listTablesTool(for: $0, settings: settings),
                Self.describeTableTool(for: $0),
                Self.previewTableTool(for: $0, settings: settings),
                Self.queryTool(for: $0, settings: settings)
            ]
        }
        return ListTools.Result(tools: tools)
    }

    func callTool(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        do {
            let settings = settingsProvider()
            guard settings.isEnabled else {
                throw MCPServiceError.disabled
            }
            let connections = try connectionReferences()

            if parameters.name == Self.listConnectionsToolName {
                guard parameters.arguments?.isEmpty != false else {
                    throw MCPServiceError.unexpectedArguments
                }
                let output = MCPConnectionListOutput(
                    readOnly: settings.isReadOnly,
                    connections: connections.map {
                        MCPConnectionOutput(
                            id: $0.connection.id.uuidString,
                            workspace: $0.workspaceName,
                            name: $0.connection.name,
                            engine: $0.connection.engineName,
                            endpoint: $0.connection.endpoint,
                            listTablesTool: Self.listTablesToolName(for: $0.connection),
                            describeTableTool: Self.describeTableToolName(for: $0.connection),
                            previewTableTool: Self.previewTableToolName(for: $0.connection),
                            queryTool: Self.queryToolName(for: $0.connection)
                        )
                    }
                )
                return try Self.successResult(output)
            }

            for reference in connections {
                switch parameters.name {
                case Self.listTablesToolName(for: reference.connection):
                    return try await listTables(
                        reference: reference,
                        arguments: parameters.arguments ?? [:],
                        settings: settings
                    )
                case Self.describeTableToolName(for: reference.connection):
                    return try await describeTable(
                        reference: reference,
                        arguments: parameters.arguments ?? [:],
                        settings: settings
                    )
                case Self.previewTableToolName(for: reference.connection):
                    return try await previewTable(
                        reference: reference,
                        arguments: parameters.arguments ?? [:],
                        settings: settings
                    )
                case Self.queryToolName(for: reference.connection):
                    return try await query(
                        reference: reference,
                        arguments: parameters.arguments ?? [:],
                        settings: settings
                    )
                default:
                    continue
                }
            }
            throw MCPServiceError.unknownTool(parameters.name)
        } catch {
            return Self.errorResult(error.localizedDescription)
        }
    }

    static func listTablesToolName(for connection: DatabaseConnection) -> String {
        toolName(prefix: "list_tables", connection: connection)
    }

    static func describeTableToolName(for connection: DatabaseConnection) -> String {
        toolName(prefix: "describe_table", connection: connection)
    }

    static func previewTableToolName(for connection: DatabaseConnection) -> String {
        toolName(prefix: "preview_table", connection: connection)
    }

    static func queryToolName(for connection: DatabaseConnection) -> String {
        toolName(prefix: "query", connection: connection)
    }

    private static func toolName(
        prefix: String,
        connection: DatabaseConnection
    ) -> String {
        let slug = connection.name.lowercased().unicodeScalars.reduce(into: "") { result, scalar in
            if (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57) {
                result.unicodeScalars.append(scalar)
            } else if result.last != "_" {
                result.append("_")
            }
        }
        let normalized = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let readableName = String((normalized.isEmpty ? "connection" : normalized).prefix(14))
        let identifier = connection.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(prefix)_\(readableName)_\(identifier)"
    }

    private func connectionReferences() throws -> [MCPConnectionReference] {
        let state = try persistence.loadValidated() ?? .initial
        return state.workspaces.flatMap { workspace in
            workspace.connections.map {
                MCPConnectionReference(workspaceName: workspace.name, connection: $0)
            }
        }
    }

    private static func listConnectionsTool() -> Tool {
        Tool(
            name: listConnectionsToolName,
            title: "List Selektos Connections",
            description: "List database connections exposed by Selektos and the tool name for querying each one.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ]),
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "readOnly": .object(["type": .string("boolean")]),
                    "connections": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("object")])
                    ])
                ]),
                "required": .array([.string("readOnly"), .string("connections")])
            ])
        )
    }

    private static func listTablesTool(
        for reference: MCPConnectionReference,
        settings: MCPSettings
    ) -> Tool {
        Tool(
            name: listTablesToolName(for: reference.connection),
            title: "List tables — \(reference.connection.name)",
            description: "List user tables and views available through the \(reference.connection.name) connection.",
            inputSchema: metadataInputSchema(
                connection: reference.connection,
                settings: settings,
                requiresTable: false,
                includesMaximumRows: true
            ),
            annotations: readOnlyAnnotations,
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "connection": .object(["type": .string("string")]),
                    "engine": .object(["type": .string("string")]),
                    "endpoint": .object(["type": .string("string")]),
                    "database": .object(["type": .string("string")]),
                    "tables": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "rowCount": .object(["type": .string("integer")]),
                    "truncated": .object(["type": .string("boolean")])
                ]),
                "required": .array([
                    .string("connection"), .string("engine"), .string("endpoint"),
                    .string("database"), .string("tables"), .string("rowCount"),
                    .string("truncated")
                ])
            ])
        )
    }

    private static func describeTableTool(for reference: MCPConnectionReference) -> Tool {
        Tool(
            name: describeTableToolName(for: reference.connection),
            title: "Describe table — \(reference.connection.name)",
            description: "Return column names, types, nullability, primary-key status, and defaults for a table on \(reference.connection.name).",
            inputSchema: metadataInputSchema(
                connection: reference.connection,
                settings: nil,
                requiresTable: true,
                includesMaximumRows: false
            ),
            annotations: readOnlyAnnotations,
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "connection": .object(["type": .string("string")]),
                    "engine": .object(["type": .string("string")]),
                    "endpoint": .object(["type": .string("string")]),
                    "database": .object(["type": .string("string")]),
                    "matches": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "truncated": .object(["type": .string("boolean")])
                ]),
                "required": .array([
                    .string("connection"), .string("engine"), .string("endpoint"),
                    .string("database"), .string("matches"), .string("truncated")
                ])
            ])
        )
    }

    private static func previewTableTool(
        for reference: MCPConnectionReference,
        settings: MCPSettings
    ) -> Tool {
        Tool(
            name: previewTableToolName(for: reference.connection),
            title: "Preview table — \(reference.connection.name)",
            description: "Read a limited sample of rows from a table on \(reference.connection.name) without writing SQL.",
            inputSchema: metadataInputSchema(
                connection: reference.connection,
                settings: settings,
                requiresTable: true,
                includesMaximumRows: true
            ),
            annotations: readOnlyAnnotations,
            outputSchema: queryOutputSchema
        )
    }

    private static func queryTool(
        for reference: MCPConnectionReference,
        settings: MCPSettings
    ) -> Tool {
        var properties: [String: Value] = [
            "sql": .object([
                "type": .string("string"),
                "description": .string("SQL to execute against this saved connection.")
            ]),
            "max_rows": .object([
                "type": .string("integer"),
                "minimum": .int(1),
                "maximum": .int(settings.maximumRows),
                "default": .int(settings.maximumRows),
                "description": .string("Maximum rows returned to the agent.")
            ])
        ]
        if reference.connection.connectionKind == .postgresql {
            properties["database"] = .object([
                "type": .string("string"),
                "description": .string("Optional PostgreSQL database override for this server.")
            ])
            properties["schema"] = .object([
                "type": .string("string"),
                "description": .string("Optional PostgreSQL schema placed first on search_path.")
            ])
        }

        let accessDescription = settings.isReadOnly
            ? "Read-only mode is enabled; mutating SQL is rejected."
            : "Read/write mode is enabled; this tool can modify the database."
        return Tool(
            name: queryToolName(for: reference.connection),
            title: reference.connection.name,
            description: "Query the \(reference.connection.engineName) connection “\(reference.connection.name)” in workspace “\(reference.workspaceName)” at \(reference.connection.endpoint). \(accessDescription)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([.string("sql")]),
                "additionalProperties": .bool(false)
            ]),
            annotations: .init(
                readOnlyHint: settings.isReadOnly,
                destructiveHint: settings.isReadOnly ? false : true,
                idempotentHint: settings.isReadOnly ? true : nil,
                openWorldHint: false
            ),
            outputSchema: queryOutputSchema
        )
    }

    private func listTables(
        reference: MCPConnectionReference,
        arguments: [String: Value],
        settings: MCPSettings
    ) async throws -> CallTool.Result {
        let allowedArguments: Set<String> = reference.connection.connectionKind == .postgresql
            ? ["database", "schema", "max_rows"]
            : ["max_rows"]
        try Self.validate(arguments: arguments, allowed: allowedArguments)
        let maximumRows = try Self.maximumRows(in: arguments, settings: settings)
        let target = try Self.targetConnection(reference: reference, arguments: arguments)
        let limit = maximumRows + 1

        let sql: String
        switch target.connection.connectionKind {
        case .postgresql:
            let schemaFilter = target.schema.map {
                "\n  AND table_schema = \(Self.sqlStringLiteral($0))"
            } ?? ""
            sql = """
            SELECT table_schema, table_name, lower(table_type) AS table_type
            FROM information_schema.tables
            WHERE table_type IN ('BASE TABLE', 'VIEW', 'FOREIGN')
              AND table_schema <> 'information_schema'
              AND table_schema NOT LIKE 'pg\\_%' ESCAPE '\\'\(schemaFilter)
            ORDER BY table_schema, table_name
            LIMIT \(limit);
            """
        case .cloudflareD1:
            sql = """
            SELECT 'main' AS table_schema, name AS table_name, type AS table_type
            FROM sqlite_schema
            WHERE type IN ('table', 'view')
              AND name NOT LIKE 'sqlite_%'
              AND name NOT GLOB '_cf_*'
            ORDER BY name
            LIMIT \(limit);
            """
        }

        let result = try await queryExecutor.execute(
            MCPQueryRequest(
                connection: target.connection,
                sql: sql,
                schema: nil,
                maximumRows: limit,
                readOnly: true
            )
        )
        let tables = result.rows.prefix(maximumRows).compactMap { row -> MCPTableOutput? in
            let values = Self.rowDictionary(columns: result.columns, row: row)
            guard let schema = values["table_schema"],
                  let name = values["table_name"],
                  let type = values["table_type"] else {
                return nil
            }
            return MCPTableOutput(schema: schema, name: name, type: type)
        }
        return try Self.successResult(
            MCPTableListOutput(
                connection: target.connection.name,
                engine: target.connection.engineName,
                endpoint: target.connection.endpoint,
                database: Self.databaseName(for: target.connection),
                tables: tables,
                rowCount: tables.count,
                truncated: result.wasTruncated || result.rows.count > maximumRows
            )
        )
    }

    private func describeTable(
        reference: MCPConnectionReference,
        arguments: [String: Value],
        settings: MCPSettings
    ) async throws -> CallTool.Result {
        let allowedArguments: Set<String> = reference.connection.connectionKind == .postgresql
            ? ["database", "schema", "table"]
            : ["table"]
        try Self.validate(arguments: arguments, allowed: allowedArguments)
        let table = try Self.requiredString("table", in: arguments)
        let target = try Self.targetConnection(reference: reference, arguments: arguments)
        let limit = settings.maximumRows + 1

        let sql: String
        switch target.connection.connectionKind {
        case .postgresql:
            let schemaFilter = target.schema.map {
                "\n  AND c.table_schema = \(Self.sqlStringLiteral($0))"
            } ?? ""
            sql = """
            WITH primary_keys AS (
                SELECT kcu.table_schema, kcu.table_name, kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON kcu.constraint_name = tc.constraint_name
                 AND kcu.constraint_schema = tc.constraint_schema
                WHERE tc.constraint_type = 'PRIMARY KEY'
            )
            SELECT
                c.table_schema,
                c.table_name,
                c.column_name,
                c.data_type,
                c.is_nullable,
                CASE WHEN pk.column_name IS NULL THEN 'false' ELSE 'true' END AS is_primary_key,
                c.column_default
            FROM information_schema.columns c
            LEFT JOIN primary_keys pk
              ON pk.table_schema = c.table_schema
             AND pk.table_name = c.table_name
             AND pk.column_name = c.column_name
            WHERE c.table_name = \(Self.sqlStringLiteral(table))
              AND c.table_schema <> 'information_schema'
              AND c.table_schema NOT LIKE 'pg\\_%' ESCAPE '\\'\(schemaFilter)
            ORDER BY c.table_schema, c.table_name, c.ordinal_position
            LIMIT \(limit);
            """
        case .cloudflareD1:
            sql = "PRAGMA table_info(\(Self.sqlStringLiteral(table)));"
        }

        let result = try await queryExecutor.execute(
            MCPQueryRequest(
                connection: target.connection,
                sql: sql,
                schema: nil,
                maximumRows: limit,
                readOnly: true
            )
        )
        let descriptions = Self.tableDescriptions(
            from: result,
            connectionKind: target.connection.connectionKind,
            fallbackSchema: target.schema ?? "main",
            fallbackTable: table,
            maximumRows: settings.maximumRows
        )
        guard !descriptions.isEmpty else {
            throw MCPServiceError.tableNotFound(table)
        }
        return try Self.successResult(
            MCPTableDescriptionListOutput(
                connection: target.connection.name,
                engine: target.connection.engineName,
                endpoint: target.connection.endpoint,
                database: Self.databaseName(for: target.connection),
                matches: descriptions,
                truncated: result.wasTruncated || result.rows.count > settings.maximumRows
            )
        )
    }

    private func previewTable(
        reference: MCPConnectionReference,
        arguments: [String: Value],
        settings: MCPSettings
    ) async throws -> CallTool.Result {
        let allowedArguments: Set<String> = reference.connection.connectionKind == .postgresql
            ? ["database", "schema", "table", "max_rows"]
            : ["table", "max_rows"]
        try Self.validate(arguments: arguments, allowed: allowedArguments)
        let table = try Self.requiredString("table", in: arguments)
        let maximumRows = try Self.maximumRows(in: arguments, settings: settings)
        let target = try Self.targetConnection(reference: reference, arguments: arguments)
        let qualifiedTable: String
        if target.connection.connectionKind == .postgresql, let schema = target.schema {
            qualifiedTable = "\(Self.sqlIdentifier(schema)).\(Self.sqlIdentifier(table))"
        } else {
            qualifiedTable = Self.sqlIdentifier(table)
        }
        let result = try await queryExecutor.execute(
            MCPQueryRequest(
                connection: target.connection,
                sql: "SELECT * FROM \(qualifiedTable) LIMIT \(maximumRows + 1);",
                schema: target.schema,
                maximumRows: maximumRows + 1,
                readOnly: true
            )
        )
        return try Self.successResult(
            Self.queryOutput(
                result: result,
                connection: target.connection,
                schema: target.schema,
                maximumRows: maximumRows,
                readOnly: true
            )
        )
    }

    private func query(
        reference: MCPConnectionReference,
        arguments: [String: Value],
        settings: MCPSettings
    ) async throws -> CallTool.Result {
        let allowedArguments: Set<String> = reference.connection.connectionKind == .postgresql
            ? ["sql", "database", "schema", "max_rows"]
            : ["sql", "max_rows"]
        try Self.validate(arguments: arguments, allowed: allowedArguments)
        let sql = try Self.requiredString("sql", in: arguments)
        let maximumRows = try Self.maximumRows(in: arguments, settings: settings)
        let target = try Self.targetConnection(reference: reference, arguments: arguments)
        let result = try await queryExecutor.execute(
            MCPQueryRequest(
                connection: target.connection,
                sql: sql,
                schema: target.schema,
                maximumRows: maximumRows,
                readOnly: settings.isReadOnly
            )
        )
        return try Self.successResult(
            Self.queryOutput(
                result: result,
                connection: target.connection,
                schema: target.schema,
                maximumRows: maximumRows,
                readOnly: settings.isReadOnly
            )
        )
    }

    private static func metadataInputSchema(
        connection: DatabaseConnection,
        settings: MCPSettings?,
        requiresTable: Bool,
        includesMaximumRows: Bool
    ) -> Value {
        var properties: [String: Value] = [:]
        var required: [Value] = []
        if requiresTable {
            properties["table"] = .object([
                "type": .string("string"),
                "description": .string("Table or view name.")
            ])
            required.append(.string("table"))
        }
        if connection.connectionKind == .postgresql {
            properties["database"] = .object([
                "type": .string("string"),
                "description": .string("Optional PostgreSQL database override for this server.")
            ])
            properties["schema"] = .object([
                "type": .string("string"),
                "description": .string("Optional PostgreSQL schema filter.")
            ])
        }
        if includesMaximumRows, let settings {
            properties["max_rows"] = .object([
                "type": .string("integer"),
                "minimum": .int(1),
                "maximum": .int(settings.maximumRows),
                "default": .int(settings.maximumRows),
                "description": .string("Maximum rows returned to the agent.")
            ])
        }
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required)
        }
        return .object(schema)
    }

    private static var readOnlyAnnotations: Tool.Annotations {
        .init(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    }

    private static var queryOutputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "connection": .object(["type": .string("string")]),
                "engine": .object(["type": .string("string")]),
                "endpoint": .object(["type": .string("string")]),
                "database": .object(["type": .string("string")]),
                "schema": .object(["type": .array([.string("string"), .string("null")])]),
                "command": .object(["type": .string("string")]),
                "columns": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "rows": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")])
                    ])
                ]),
                "rowCount": .object(["type": .string("integer")]),
                "truncated": .object(["type": .string("boolean")]),
                "maximumRows": .object(["type": .string("integer")]),
                "durationMilliseconds": .object(["type": .string("number")]),
                "readOnly": .object(["type": .string("boolean")])
            ]),
            "required": .array([
                .string("connection"), .string("engine"), .string("endpoint"),
                .string("database"), .string("command"), .string("columns"),
                .string("rows"), .string("rowCount"), .string("truncated"),
                .string("maximumRows"), .string("durationMilliseconds"),
                .string("readOnly")
            ])
        ])
    }

    private static func validate(
        arguments: [String: Value],
        allowed: Set<String>
    ) throws {
        if let unexpected = arguments.keys.first(where: { !allowed.contains($0) }) {
            throw MCPServiceError.unexpectedArgument(unexpected)
        }
    }

    private static func requiredString(
        _ name: String,
        in arguments: [String: Value]
    ) throws -> String {
        guard let value = arguments[name]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            throw MCPServiceError.invalidStringArgument(name)
        }
        return value
    }

    private static func optionalString(
        _ name: String,
        in arguments: [String: Value]
    ) throws -> String? {
        guard let rawValue = arguments[name] else { return nil }
        guard let value = rawValue.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            throw MCPServiceError.invalidStringArgument(name)
        }
        return value
    }

    private static func maximumRows(
        in arguments: [String: Value],
        settings: MCPSettings
    ) throws -> Int {
        let maximumRows: Int
        if let value = arguments["max_rows"] {
            guard let requestedRows = value.intValue else {
                throw MCPServiceError.invalidMaximumRows(settings.maximumRows)
            }
            maximumRows = requestedRows
        } else {
            maximumRows = settings.maximumRows
        }
        guard maximumRows > 0, maximumRows <= settings.maximumRows else {
            throw MCPServiceError.invalidMaximumRows(settings.maximumRows)
        }
        return maximumRows
    }

    private static func targetConnection(
        reference: MCPConnectionReference,
        arguments: [String: Value]
    ) throws -> (connection: DatabaseConnection, schema: String?) {
        var connection = reference.connection
        guard connection.connectionKind == .postgresql else {
            return (connection, nil)
        }
        if let database = try optionalString("database", in: arguments) {
            connection.database = database
        }
        return (connection, try optionalString("schema", in: arguments))
    }

    private static func queryOutput(
        result: QueryResult,
        connection: DatabaseConnection,
        schema: String?,
        maximumRows: Int,
        readOnly: Bool
    ) -> MCPQueryOutput {
        let rows = result.rows.prefix(maximumRows).map(\.values)
        return MCPQueryOutput(
            connection: connection.name,
            engine: connection.engineName,
            endpoint: connection.endpoint,
            database: databaseName(for: connection),
            schema: schema,
            command: result.command,
            columns: result.columns,
            rows: rows,
            rowCount: rows.count,
            truncated: result.wasTruncated || result.rows.count > maximumRows,
            maximumRows: maximumRows,
            durationMilliseconds: result.durationMilliseconds,
            readOnly: readOnly
        )
    }

    private static func tableDescriptions(
        from result: QueryResult,
        connectionKind: ConnectionKind,
        fallbackSchema: String,
        fallbackTable: String,
        maximumRows: Int
    ) -> [MCPTableDescriptionOutput] {
        var columnsByTable: [MCPTableIdentity: [MCPColumnOutput]] = [:]
        for row in result.rows.prefix(maximumRows) {
            let values = rowDictionary(columns: result.columns, row: row)
            let schema: String
            let table: String
            let column: MCPColumnOutput

            switch connectionKind {
            case .postgresql:
                guard let tableSchema = values["table_schema"],
                      let tableName = values["table_name"],
                      let columnName = values["column_name"],
                      let dataType = values["data_type"] else {
                    continue
                }
                schema = tableSchema
                table = tableName
                column = MCPColumnOutput(
                    name: columnName,
                    dataType: dataType,
                    nullable: values["is_nullable"] == "YES",
                    primaryKey: values["is_primary_key"] == "true",
                    defaultValue: nilIfDatabaseNull(values["column_default"])
                )
            case .cloudflareD1:
                guard let columnName = values["name"] else { continue }
                schema = fallbackSchema
                table = fallbackTable
                column = MCPColumnOutput(
                    name: columnName,
                    dataType: values["type"].flatMap { $0.isEmpty ? nil : $0 } ?? "ANY",
                    nullable: values["notnull"] != "1",
                    primaryKey: values["pk"] != "0",
                    defaultValue: nilIfDatabaseNull(values["dflt_value"])
                )
            }
            columnsByTable[MCPTableIdentity(schema: schema, name: table), default: []]
                .append(column)
        }
        return columnsByTable.keys.sorted {
            ($0.schema, $0.name) < ($1.schema, $1.name)
        }.map {
            MCPTableDescriptionOutput(
                schema: $0.schema,
                name: $0.name,
                columns: columnsByTable[$0, default: []]
            )
        }
    }

    private static func rowDictionary(
        columns: [String],
        row: QueryResultRow
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(columns, row.values))
    }

    private static func databaseName(for connection: DatabaseConnection) -> String {
        switch connection.connectionKind {
        case .postgresql:
            connection.database
        case .cloudflareD1:
            connection.d1Database ?? connection.database
        }
    }

    private static func nilIfDatabaseNull(_ value: String?) -> String? {
        guard let value, value != "NULL" else { return nil }
        return value
    }

    private static func sqlStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func sqlIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func successResult<Output: Codable>(_ output: Output) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(output), as: UTF8.self)
        return try CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: output,
            isError: false
        )
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

enum MCPServerCommand {
    static func run() async throws {
        MCPPreferences.registerDefaults()
        let startupSettings = MCPPreferences.current
        guard startupSettings.isEnabled else {
            throw MCPServiceError.disabled
        }

        let toolService = MCPToolService(settingsProvider: {
            MCPSettings.sessionSettings(
                startup: startupSettings,
                current: MCPPreferences.current
            )
        })
        let server = Server(
            name: "selektos",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0.0",
            title: "Selektos",
            instructions: "Use list_connections to discover saved databases and their table-listing, table-description, row-preview, and SQL query tools. Query results are capped by the MCP row limit configured in Selektos.",
            capabilities: .init(tools: .init(listChanged: false)),
            configuration: .strict
        )

        await server.withMethodHandler(ListTools.self) { _ in
            try await toolService.listTools()
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await toolService.callTool(parameters)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
        await server.stop()
    }
}

private struct MCPConnectionReference: Sendable {
    let workspaceName: String
    let connection: DatabaseConnection
}

private struct MCPConnectionOutput: Codable, Sendable {
    let id: String
    let workspace: String
    let name: String
    let engine: String
    let endpoint: String
    let listTablesTool: String
    let describeTableTool: String
    let previewTableTool: String
    let queryTool: String
}

private struct MCPConnectionListOutput: Codable, Sendable {
    let readOnly: Bool
    let connections: [MCPConnectionOutput]
}

private struct MCPTableOutput: Codable, Sendable {
    let schema: String
    let name: String
    let type: String
}

private struct MCPTableListOutput: Codable, Sendable {
    let connection: String
    let engine: String
    let endpoint: String
    let database: String
    let tables: [MCPTableOutput]
    let rowCount: Int
    let truncated: Bool
}

private struct MCPColumnOutput: Codable, Sendable {
    let name: String
    let dataType: String
    let nullable: Bool
    let primaryKey: Bool
    let defaultValue: String?
}

private struct MCPTableDescriptionOutput: Codable, Sendable {
    let schema: String
    let name: String
    let columns: [MCPColumnOutput]
}

private struct MCPTableDescriptionListOutput: Codable, Sendable {
    let connection: String
    let engine: String
    let endpoint: String
    let database: String
    let matches: [MCPTableDescriptionOutput]
    let truncated: Bool
}

private struct MCPTableIdentity: Hashable, Sendable {
    let schema: String
    let name: String
}

private struct MCPQueryOutput: Codable, Sendable {
    let connection: String
    let engine: String
    let endpoint: String
    let database: String
    let schema: String?
    let command: String
    let columns: [String]
    let rows: [[String]]
    let rowCount: Int
    let truncated: Bool
    let maximumRows: Int
    let durationMilliseconds: Double
    let readOnly: Bool
}

private enum MCPServiceError: LocalizedError {
    case disabled
    case invalidMaximumRows(Int)
    case invalidStringArgument(String)
    case tableNotFound(String)
    case unexpectedArgument(String)
    case unexpectedArguments
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "The Selektos MCP server is disabled. Enable it in Selektos Settings."
        case .invalidMaximumRows(let limit):
            "max_rows must be between 1 and the configured limit of \(limit)."
        case .invalidStringArgument(let name):
            "The \(name) argument is required and must be a non-empty string."
        case .tableNotFound(let table):
            "No accessible table or view named \(table) was found."
        case .unexpectedArgument(let name):
            "Unexpected argument: \(name)."
        case .unexpectedArguments:
            "This tool does not accept arguments."
        case .unknownTool(let name):
            "Unknown Selektos tool: \(name). Refresh the MCP tool list."
        }
    }
}
