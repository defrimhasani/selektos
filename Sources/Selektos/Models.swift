import Foundation

struct AppState: Codable {
    var workspaces: [Workspace]
    var selectedWorkspaceID: UUID?

    static let initial = AppState(
        workspaces: [Workspace(name: "My Workspace")],
        selectedWorkspaceID: nil
    )
}

struct Workspace: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var connections: [DatabaseConnection] = []
    var queryTabs: [QueryTab] = [QueryTab()]
    var selectedQueryID: UUID?

    init(name: String) {
        self.name = name
        selectedQueryID = queryTabs.first?.id
    }
}

struct DatabaseConnection: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: ConnectionKind?
    var name: String
    var host: String
    var port: Int
    var database: String
    var username: String
    var tlsMode: TLSMode
    var labels: [ConnectionLabel]
    var d1Database: String?
    var wranglerPath: String?
    var wranglerProfile: String?

    var connectionKind: ConnectionKind { kind ?? .postgresql }
    var endpoint: String {
        switch connectionKind {
        case .postgresql: return "\(host):\(port)/\(database)"
        case .cloudflareD1: return d1Database ?? database
        }
    }
    var engineName: String {
        switch connectionKind {
        case .postgresql: "PostgreSQL"
        case .cloudflareD1: "Cloudflare D1"
        }
    }
}

enum ConnectionKind: String, Codable, CaseIterable, Identifiable {
    case postgresql
    case cloudflareD1

    var id: Self { self }
    var title: String {
        switch self {
        case .postgresql: "PostgreSQL"
        case .cloudflareD1: "Cloudflare D1"
        }
    }
}

enum TLSMode: String, Codable, CaseIterable, Identifiable {
    case prefer
    case require
    case disable

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct ConnectionLabel: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: LabelColor
}

enum LabelColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray
    var id: Self { self }
}

struct DatabaseSchema: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let tables: [DatabaseTable]
}

struct DatabaseTable: Identifiable, Hashable, Sendable {
    var id: String { "\(schema).\(name)" }
    let schema: String
    let name: String
    let columns: [DatabaseColumn]
}

struct DatabaseColumn: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let dataType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
}

struct QueryTab: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "Untitled Query"
    var sql = "SELECT version();"
    var connectionID: UUID?
    var schema: String?
}

struct QueryResult: Identifiable, Sendable {
    let id = UUID()
    let columns: [String]
    let rows: [QueryResultRow]
    let command: String
    let duration: Duration

    var durationText: String {
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.0f ms", milliseconds)
    }
}

struct QueryResultRow: Identifiable, Sendable {
    let id: Int
    let values: [String]
}

enum ConnectionStatus: Equatable {
    case disconnected
    case loading
    case connected
    case failed(String)
}

struct ConnectionDraft {
    var kind = ConnectionKind.postgresql
    var name = ""
    var host = "localhost"
    var port = 5432
    var database = "postgres"
    var username = NSUserName()
    var password = ""
    var tlsMode = TLSMode.prefer
    var labels = "DEV"
    var d1Database = ""
    var wranglerPath = "wrangler"
    var wranglerProfile = ""

    init() {}

    init(connection: DatabaseConnection, password: String) {
        kind = connection.connectionKind
        name = connection.name
        host = connection.host
        port = connection.port
        database = connection.database
        username = connection.username
        self.password = password
        tlsMode = connection.tlsMode
        labels = connection.labels.map(\.name).joined(separator: ", ")
        d1Database = connection.d1Database ?? ""
        wranglerPath = connection.wranglerPath ?? "wrangler"
        wranglerProfile = connection.wranglerProfile ?? ""
    }
}

struct D1Database: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}
