import MCP
import XCTest
@testable import Selektos

final class MCPToolServiceTests: XCTestCase {
    func testListsMetadataPreviewAndQueryToolsPerSavedConnection() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: true, maximumRows: 500)
            },
            queryExecutor: RecordingMCPQueryExecutor()
        )

        let result = try await service.listTools()

        XCTAssertEqual(result.tools.count, 1 + fixture.connections.count * 4)
        XCTAssertEqual(result.tools.first?.name, MCPToolService.listConnectionsToolName)
        for connection in fixture.connections {
            let toolNames = [
                MCPToolService.listTablesToolName(for: connection),
                MCPToolService.describeTableToolName(for: connection),
                MCPToolService.previewTableToolName(for: connection),
                MCPToolService.queryToolName(for: connection)
            ]
            for toolName in toolNames {
                let tool = try XCTUnwrap(result.tools.first(where: { $0.name == toolName }))
                XCTAssertEqual(tool.annotations.readOnlyHint, true)
                XCTAssertEqual(tool.annotations.destructiveHint, false)
                XCTAssertTrue(tool.description?.contains(connection.name) == true)
                XCTAssertLessThanOrEqual(tool.name.count, 64)
                XCTAssertTrue(
                    tool.name.hasSuffix(
                        connection.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                    )
                )
            }
        }
    }

    func testListTablesUsesReadOnlyMetadataQuery() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(
            fixture.connections.first(where: { $0.connectionKind == .cloudflareD1 })
        )
        let executor = RecordingMCPQueryExecutor(
            result: QueryResult(
                columns: ["table_schema", "table_name", "table_type"],
                rows: [
                    QueryResultRow(id: 0, values: ["main", "parties", "table"]),
                    QueryResultRow(id: 1, values: ["main", "invoices", "table"])
                ],
                command: "SELECT",
                duration: .milliseconds(2)
            )
        )
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: false, maximumRows: 100)
            },
            queryExecutor: executor
        )

        let result = await service.callTool(
            .init(
                name: MCPToolService.listTablesToolName(for: connection),
                arguments: ["max_rows": .int(10)]
            )
        )

        XCTAssertEqual(result.isError, false)
        let tables = result.structuredContent?.objectValue?["tables"]?.arrayValue
        XCTAssertEqual(tables?.count, 2)
        XCTAssertEqual(tables?.first?.objectValue?["name"]?.stringValue, "parties")
        let recordedRequest = await executor.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertTrue(request.sql.contains("sqlite_schema"))
        XCTAssertEqual(request.maximumRows, 11)
        XCTAssertTrue(request.readOnly)
    }

    func testDescribeTableReturnsD1ColumnMetadata() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(
            fixture.connections.first(where: { $0.connectionKind == .cloudflareD1 })
        )
        let executor = RecordingMCPQueryExecutor(
            result: QueryResult(
                columns: ["cid", "dflt_value", "name", "notnull", "pk", "type"],
                rows: [
                    QueryResultRow(
                        id: 0,
                        values: ["0", "NULL", "id", "1", "1", "TEXT"]
                    ),
                    QueryResultRow(
                        id: 1,
                        values: ["1", "NULL", "display_name", "0", "0", "TEXT"]
                    )
                ],
                command: "PRAGMA",
                duration: .milliseconds(2)
            )
        )
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: true, maximumRows: 100)
            },
            queryExecutor: executor
        )

        let result = await service.callTool(
            .init(
                name: MCPToolService.describeTableToolName(for: connection),
                arguments: ["table": .string("parties")]
            )
        )

        XCTAssertEqual(result.isError, false)
        let matches = result.structuredContent?.objectValue?["matches"]?.arrayValue
        let columns = matches?.first?.objectValue?["columns"]?.arrayValue
        XCTAssertEqual(matches?.first?.objectValue?["name"]?.stringValue, "parties")
        XCTAssertEqual(columns?.count, 2)
        XCTAssertEqual(columns?.first?.objectValue?["primaryKey"]?.boolValue, true)
        let recordedRequest = await executor.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.sql, "PRAGMA table_info('parties');")
        XCTAssertTrue(request.readOnly)
    }

    func testPreviewTableQuotesIdentifiersAndAlwaysUsesReadOnlyExecution() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(
            fixture.connections.first(where: { $0.connectionKind == .cloudflareD1 })
        )
        let executor = RecordingMCPQueryExecutor()
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: false, maximumRows: 100)
            },
            queryExecutor: executor
        )

        let result = await service.callTool(
            .init(
                name: MCPToolService.previewTableToolName(for: connection),
                arguments: [
                    "table": .string("party\"records"),
                    "max_rows": .int(5)
                ]
            )
        )

        XCTAssertEqual(result.isError, false)
        let recordedRequest = await executor.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.sql, "SELECT * FROM \"party\"\"records\" LIMIT 6;")
        XCTAssertEqual(request.maximumRows, 6)
        XCTAssertTrue(request.readOnly)
        XCTAssertEqual(result.structuredContent?.objectValue?["readOnly"]?.boolValue, true)
    }

    func testPostgresDescriptionEscapesFiltersAndOverridesDatabase() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(
            fixture.connections.first(where: { $0.connectionKind == .postgresql })
        )
        let executor = RecordingMCPQueryExecutor(
            result: QueryResult(
                columns: [
                    "table_schema",
                    "table_name",
                    "column_name",
                    "data_type",
                    "is_nullable",
                    "column_default",
                    "is_primary_key"
                ],
                rows: [
                    QueryResultRow(
                        id: 0,
                        values: [
                            "sales' archive",
                            "parties",
                            "id",
                            "uuid",
                            "NO",
                            "NULL",
                            "true"
                        ]
                    )
                ],
                command: "WITH",
                duration: .milliseconds(2)
            )
        )
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: false, maximumRows: 100)
            },
            queryExecutor: executor
        )

        let result = await service.callTool(
            .init(
                name: MCPToolService.describeTableToolName(for: connection),
                arguments: [
                    "table": .string(" parties "),
                    "schema": .string(" sales' archive "),
                    "database": .string(" analytics ")
                ]
            )
        )

        XCTAssertEqual(result.isError, false)
        let matches = result.structuredContent?.objectValue?["matches"]?.arrayValue
        XCTAssertEqual(matches?.first?.objectValue?["schema"]?.stringValue, "sales' archive")
        XCTAssertEqual(
            matches?.first?.objectValue?["columns"]?.arrayValue?.first?
                .objectValue?["primaryKey"]?.boolValue,
            true
        )
        let recordedRequest = await executor.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.connection.database, "analytics")
        XCTAssertTrue(request.sql.contains("c.table_name = 'parties'"))
        XCTAssertTrue(request.sql.contains("c.table_schema = 'sales'' archive'"))
        XCTAssertTrue(request.readOnly)
    }

    func testListConnectionsReturnsAllGeneratedToolNames() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(fixture.connections.first)
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: true, maximumRows: 100)
            },
            queryExecutor: RecordingMCPQueryExecutor()
        )

        let result = await service.callTool(
            .init(name: MCPToolService.listConnectionsToolName)
        )

        XCTAssertEqual(result.isError, false)
        let connections = result.structuredContent?.objectValue?["connections"]?.arrayValue
        let output = try XCTUnwrap(
            connections?.first(where: {
                $0.objectValue?["id"]?.stringValue == connection.id.uuidString
            })?.objectValue
        )
        XCTAssertEqual(
            output["listTablesTool"]?.stringValue,
            MCPToolService.listTablesToolName(for: connection)
        )
        XCTAssertEqual(
            output["describeTableTool"]?.stringValue,
            MCPToolService.describeTableToolName(for: connection)
        )
        XCTAssertEqual(
            output["previewTableTool"]?.stringValue,
            MCPToolService.previewTableToolName(for: connection)
        )
        XCTAssertEqual(
            output["queryTool"]?.stringValue,
            MCPToolService.queryToolName(for: connection)
        )
    }

    func testQueryToolRoutesConnectionAndReadOnlyPolicy() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let executor = RecordingMCPQueryExecutor()
        let connection = try XCTUnwrap(
            fixture.connections.first(where: { $0.connectionKind == .postgresql })
        )
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: true, maximumRows: 500)
            },
            queryExecutor: executor
        )

        let result = await service.callTool(
            .init(
                name: MCPToolService.queryToolName(for: connection),
                arguments: [
                    "sql": .string("SELECT * FROM users;"),
                    "database": .string("analytics"),
                    "schema": .string("reporting"),
                    "max_rows": .int(100)
                ]
            )
        )

        XCTAssertEqual(result.isError, false)
        let recordedRequest = await executor.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.connection.id, connection.id)
        XCTAssertEqual(request.connection.database, "analytics")
        XCTAssertEqual(request.schema, "reporting")
        XCTAssertEqual(request.maximumRows, 100)
        XCTAssertTrue(request.readOnly)
        XCTAssertEqual(result.structuredContent?.objectValue?["rowCount"]?.intValue, 1)
    }

    func testQueryToolRejectsRowsAboveConfiguredLimit() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(fixture.connections.first)
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: true, isReadOnly: true, maximumRows: 100)
            },
            queryExecutor: RecordingMCPQueryExecutor()
        )

        let result = await service.callTool(
            .init(
                name: MCPToolService.queryToolName(for: connection),
                arguments: [
                    "sql": .string("SELECT 1;"),
                    "max_rows": .int(101)
                ]
            )
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.description.contains("configured limit of 100"))
    }

    func testDisabledServerRejectsToolDiscoveryAndCalls() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let connection = try XCTUnwrap(fixture.connections.first)
        let service = MCPToolService(
            persistence: fixture.persistence,
            settingsProvider: {
                MCPSettings(isEnabled: false, isReadOnly: true, maximumRows: 100)
            },
            queryExecutor: RecordingMCPQueryExecutor()
        )

        do {
            _ = try await service.listTools()
            XCTFail("Expected disabled MCP discovery to fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("disabled"))
        }

        let result = await service.callTool(
            .init(
                name: MCPToolService.queryToolName(for: connection),
                arguments: ["sql": .string("SELECT 1;")]
            )
        )
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.description.contains("disabled"))
    }

    func testClientConfigurationUsesExecutablePath() throws {
        let configuration = MCPPreferences.clientConfigurationJSON(
            executableURL: URL(fileURLWithPath: "/Applications/Selektos.app/Contents/MacOS/Selektos")
        )
        let data = try XCTUnwrap(configuration.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        let selektos = try XCTUnwrap(servers["selektos"] as? [String: Any])

        XCTAssertEqual(
            selektos["command"] as? String,
            "/Applications/Selektos.app/Contents/MacOS/Selektos"
        )
        XCTAssertEqual(selektos["args"] as? [String], ["--mcp-server"])
    }

    func testSessionPolicyKeepsStartupAccessModeAndLimit() {
        let startup = MCPSettings(
            isEnabled: true,
            isReadOnly: true,
            maximumRows: 500
        )
        let current = MCPSettings(
            isEnabled: false,
            isReadOnly: false,
            maximumRows: 10_000
        )

        XCTAssertEqual(
            MCPSettings.sessionSettings(startup: startup, current: current),
            MCPSettings(isEnabled: false, isReadOnly: true, maximumRows: 500)
        )
    }

    private func makeFixture() throws -> MCPFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SelektosMCP-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let persistence = AppStatePersistence(
            fileURL: directory.appending(path: "workspaces.json")
        )
        let postgres = DatabaseConnection(
            kind: .postgresql,
            name: "Local Analytics",
            host: "localhost",
            port: 5432,
            database: "postgres",
            username: "tester",
            tlsMode: .prefer,
            labels: []
        )
        let d1 = DatabaseConnection(
            kind: .cloudflareD1,
            name: "Edge Data",
            host: "",
            port: 0,
            database: "edge-data",
            username: "",
            tlsMode: .prefer,
            labels: [],
            d1Database: "edge-data",
            wranglerPath: "wrangler",
            wranglerProfile: ""
        )
        var workspace = Workspace(name: "Tests")
        workspace.connections = [postgres, d1]
        try persistence.save(
            AppState(workspaces: [workspace], selectedWorkspaceID: workspace.id)
        )
        return MCPFixture(
            directory: directory,
            persistence: persistence,
            connections: [postgres, d1]
        )
    }
}

private struct MCPFixture {
    let directory: URL
    let persistence: AppStatePersistence
    let connections: [DatabaseConnection]

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor RecordingMCPQueryExecutor: MCPQueryExecuting {
    private var requests: [MCPQueryRequest] = []
    private let result: QueryResult

    init(result: QueryResult? = nil) {
        self.result = result ?? QueryResult(
            columns: ["value"],
            rows: [QueryResultRow(id: 0, values: ["ok"])],
            command: "SELECT",
            duration: .milliseconds(2)
        )
    }

    func execute(_ request: MCPQueryRequest) async throws -> QueryResult {
        requests.append(request)
        return result
    }

    func lastRequest() -> MCPQueryRequest? {
        requests.last
    }
}
