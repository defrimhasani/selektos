import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private(set) var state: AppState
    var schemasByConnection: [UUID: [DatabaseSchema]] = [:]
    var databasesByConnection: [UUID: [String]] = [:]
    var schemasByDatabase: [String: [DatabaseSchema]] = [:]
    var databaseStatus: [String: ConnectionStatus] = [:]
    var connectionStatus: [UUID: ConnectionStatus] = [:]
    var result: QueryResult?
    var selectedResultRowID: Int?
    var queryError: String?
    var isExecuting = false
    var lastExecutionDate: Date?
    var discoveredD1Databases: [D1Database] = []
    var isDiscoveringD1 = false
    var d1DiscoveryError: String?
    var discoveredPostgres: [DiscoveredPostgres] = []
    var isDiscoveringPostgres = false

    private let persistence: AppStatePersistence?
    private let postgres = PostgresService()
    private let postgresDiscovery = PostgresDiscoveryService()
    private let d1 = D1Service()
    private var executionTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(initialState: AppState? = nil, persistsState: Bool = true) {
        AppPreferences.registerDefaults()
        let persistence = persistsState ? AppStatePersistence() : nil
        self.persistence = persistence
        state = initialState ?? persistence?.load() ?? .initial
        if !UserDefaults.standard.bool(forKey: AppPreferences.restoreLastWorkspaceKey) {
            state.selectedWorkspaceID = state.workspaces.first?.id
        } else if state.selectedWorkspaceID == nil {
            state.selectedWorkspaceID = state.workspaces.first?.id
        }
        if updateSelectedQueryDefault() {
            save()
        }
    }

    var selectedWorkspace: Workspace? {
        guard let id = state.selectedWorkspaceID else { return nil }
        return state.workspaces.first { $0.id == id }
    }

    var selectedQuery: QueryTab? {
        guard let workspace = selectedWorkspace,
              let id = workspace.selectedQueryID else { return nil }
        return workspace.queryTabs.first { $0.id == id }
    }

    var selectedConnection: DatabaseConnection? {
        guard let workspace = selectedWorkspace else { return nil }
        if let connectionID = selectedQuery?.connectionID,
           let connection = workspace.connections.first(where: { $0.id == connectionID }) {
            return connection
        }
        return workspace.connections.first
    }

    var selectedResultRow: QueryResultRow? {
        guard let selectedResultRowID else { return nil }
        return result?.rows.first { $0.id == selectedResultRowID }
    }

    func selectResultRow(_ id: Int?) {
        guard let id else {
            selectedResultRowID = nil
            return
        }
        selectedResultRowID = result?.rows.contains(where: { $0.id == id }) == true ? id : nil
    }

    func selectWorkspace(_ id: UUID) {
        state.selectedWorkspaceID = id
        ensureQuerySelection()
        clearExecution()
        save()
    }

    func addWorkspace(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var workspace = Workspace(name: trimmed)
        workspace.queryTabs[0].sql = AppPreferences.defaultQueryText
        state.workspaces.append(workspace)
        state.selectedWorkspaceID = workspace.id
        save()
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = state.workspaces.firstIndex(where: { $0.id == id }),
              state.workspaces[index].name != trimmed else { return }
        state.workspaces[index].name = trimmed
        save()
    }

    func deleteWorkspace(_ id: UUID) {
        guard state.workspaces.count > 1,
              let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let connectionIDs = state.workspaces[index].connections.map(\.id)
        state.workspaces.remove(at: index)
        for connectionID in connectionIDs {
            schemasByConnection[connectionID] = nil
            databasesByConnection[connectionID] = nil
            schemasByDatabase = schemasByDatabase.filter { !$0.key.hasPrefix("\(connectionID):") }
            try? KeychainStore.deletePassword(for: connectionID)
        }
        if state.selectedWorkspaceID == id {
            state.selectedWorkspaceID = state.workspaces[min(index, state.workspaces.count - 1)].id
            ensureQuerySelection()
            clearExecution()
        }
        save()
    }

    func deleteSelectedWorkspace() {
        guard let id = state.selectedWorkspaceID else { return }
        deleteWorkspace(id)
    }

    func saveConnection(_ draft: ConnectionDraft, editing id: UUID? = nil) throws {
        guard let workspaceIndex = selectedWorkspaceIndex else { return }
        let labels = draft.labels.split(separator: ",").enumerated().compactMap { index, value -> ConnectionLabel? in
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let palette: [LabelColor] = [.red, .green, .orange, .blue, .purple]
            return ConnectionLabel(name: name.uppercased(), color: palette[index % palette.count])
        }

        let connection = DatabaseConnection(
            id: id ?? UUID(),
            kind: draft.kind,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: draft.host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: draft.port,
            database: draft.database.trimmingCharacters(in: .whitespacesAndNewlines),
            username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
            tlsMode: draft.tlsMode,
            labels: labels,
            d1Database: draft.kind == .cloudflareD1 ? draft.d1Database.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            wranglerPath: draft.kind == .cloudflareD1 ? draft.wranglerPath.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            wranglerProfile: draft.kind == .cloudflareD1 ? draft.wranglerProfile.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        )

        if let index = state.workspaces[workspaceIndex].connections.firstIndex(where: { $0.id == connection.id }) {
            state.workspaces[workspaceIndex].connections[index] = connection
        } else {
            state.workspaces[workspaceIndex].connections.append(connection)
        }
        if draft.kind == .postgresql {
            try KeychainStore.save(password: draft.password, for: connection.id)
        } else {
            try? KeychainStore.deletePassword(for: connection.id)
        }
        selectConnection(connection.id)
        save()
    }

    func deleteConnection(_ id: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex else { return }
        state.workspaces[workspaceIndex].connections.removeAll { $0.id == id }
        state.workspaces[workspaceIndex].queryTabs = state.workspaces[workspaceIndex].queryTabs.map { tab in
            var tab = tab
            if tab.connectionID == id { tab.connectionID = nil }
            return tab
        }
        schemasByConnection[id] = nil
        databasesByConnection[id] = nil
        schemasByDatabase = schemasByDatabase.filter { !$0.key.hasPrefix("\(id):") }
        try? KeychainStore.deletePassword(for: id)
        save()
    }

    func password(for id: UUID) -> String {
        (try? KeychainStore.password(for: id)) ?? ""
    }

    func selectConnection(_ id: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let queryIndex = selectedQueryIndex(in: workspaceIndex),
              let connection = state.workspaces[workspaceIndex].connections.first(where: { $0.id == id }) else { return }
        state.workspaces[workspaceIndex].queryTabs[queryIndex].connectionID = id
        updateQueryDefault(
            at: queryIndex,
            in: workspaceIndex,
            for: connection.connectionKind
        )
        clearExecution()
        save()
    }

    func selectQuery(_ id: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex else { return }
        state.workspaces[workspaceIndex].selectedQueryID = id
        clearExecution()
        save()
    }

    /// Schemas the focus picker can offer, with Postgres-internal schemas removed
    /// so a superuser sees only the schemas worth working in.
    var availableSchemas: [String] {
        guard let connection = selectedConnection, connection.connectionKind == .postgresql else { return [] }
        let known = schemas(for: connection.id, database: connection.database)
            ?? schemasByConnection[connection.id]
            ?? []
        var names = known.map(\.name).filter { !Self.isInternalSchema($0) }
        if let focused = selectedQuery?.schema, !names.contains(focused) {
            names.append(focused)
        }
        return names.sorted()
    }

    var completionSchemas: [DatabaseSchema] {
        guard let connection = selectedConnection else { return [] }
        return schemas(for: connection.id, database: connection.database)
            ?? schemasByConnection[connection.id]
            ?? []
    }

    func selectSchema(_ schema: String?) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let queryIndex = selectedQueryIndex(in: workspaceIndex),
              state.workspaces[workspaceIndex].queryTabs[queryIndex].schema != schema else { return }
        state.workspaces[workspaceIndex].queryTabs[queryIndex].schema = schema
        save()
    }

    /// Loads the database and schema lists the focus pickers need, without
    /// repeating work that is already done or in flight.
    func ensureMetadataLoaded(for connection: DatabaseConnection) {
        guard UserDefaults.standard.bool(forKey: AppPreferences.automaticallyLoadMetadataKey) else { return }
        switch connection.connectionKind {
        case .postgresql:
            if databasesByConnection[connection.id] == nil, connectionStatus[connection.id] != .loading {
                loadDatabases(for: connection)
            }
            if schemas(for: connection.id, database: connection.database) == nil,
               status(for: connection.id, database: connection.database) != .loading {
                loadSchema(for: connection, database: connection.database)
            }
        case .cloudflareD1:
            if schemasByConnection[connection.id] == nil, connectionStatus[connection.id] != .loading {
                loadSchema(for: connection)
            }
        }
    }

    nonisolated static func isInternalSchema(_ name: String) -> Bool {
        name == "information_schema" || name.hasPrefix("pg_")
    }

    func addQuery(sql: String? = nil, title: String = "Untitled Query", schema: String? = nil) {
        guard let workspaceIndex = selectedWorkspaceIndex else { return }
        let tab = QueryTab(
            title: title,
            sql: sql ?? AppPreferences.defaultQueryText(for: selectedConnection?.connectionKind),
            connectionID: selectedConnection?.id,
            schema: schema
        )
        state.workspaces[workspaceIndex].queryTabs.append(tab)
        state.workspaces[workspaceIndex].selectedQueryID = tab.id
        clearExecution()
        save()
    }

    func renameQuery(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let workspaceIndex = selectedWorkspaceIndex,
              let queryIndex = state.workspaces[workspaceIndex].queryTabs.firstIndex(where: { $0.id == id }),
              state.workspaces[workspaceIndex].queryTabs[queryIndex].title != trimmed else { return }
        state.workspaces[workspaceIndex].queryTabs[queryIndex].title = trimmed
        save()
    }

    func closeQuery(_ id: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex else { return }
        var workspace = state.workspaces[workspaceIndex]
        guard workspace.queryTabs.count > 1 else { return }
        workspace.queryTabs.removeAll { $0.id == id }
        if workspace.selectedQueryID == id { workspace.selectedQueryID = workspace.queryTabs.first?.id }
        state.workspaces[workspaceIndex] = workspace
        clearExecution()
        save()
    }

    func updateQueryText(_ text: String) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let queryIndex = selectedQueryIndex(in: workspaceIndex),
              state.workspaces[workspaceIndex].queryTabs[queryIndex].sql != text else { return }
        state.workspaces[workspaceIndex].queryTabs[queryIndex].sql = text
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func loadSchema(for connection: DatabaseConnection) {
        connectionStatus[connection.id] = .loading
        Task {
            do {
                let schemas: [DatabaseSchema]
                switch connection.connectionKind {
                case .postgresql:
                    let password = try KeychainStore.password(for: connection.id) ?? ""
                    schemas = try await postgres.fetchSchema(connection: connection, password: password)
                case .cloudflareD1:
                    schemas = try await d1.fetchSchema(connection: connection)
                }
                schemasByConnection[connection.id] = schemas
                connectionStatus[connection.id] = .connected
            } catch {
                connectionStatus[connection.id] = .failed(error.localizedDescription)
            }
        }
    }

    func loadDatabases(for connection: DatabaseConnection) {
        guard connection.connectionKind == .postgresql else {
            databasesByConnection[connection.id] = [connection.database]
            return
        }
        connectionStatus[connection.id] = .loading
        Task {
            do {
                let password = try KeychainStore.password(for: connection.id) ?? ""
                databasesByConnection[connection.id] = try await postgres.fetchDatabases(connection: connection, password: password)
                connectionStatus[connection.id] = .connected
            } catch {
                connectionStatus[connection.id] = .failed(error.localizedDescription)
            }
        }
    }

    func loadSchema(for connection: DatabaseConnection, database: String) {
        let key = databaseKey(connection.id, database)
        databaseStatus[key] = .loading
        Task {
            do {
                var target = connection
                target.database = database
                let schemas: [DatabaseSchema]
                switch target.connectionKind {
                case .postgresql:
                    let password = try KeychainStore.password(for: target.id) ?? ""
                    schemas = try await postgres.fetchSchema(connection: target, password: password)
                case .cloudflareD1:
                    schemas = try await d1.fetchSchema(connection: target)
                }
                schemasByDatabase[key] = schemas
                schemasByConnection[target.id] = schemas
                databaseStatus[key] = .connected
            } catch {
                databaseStatus[key] = .failed(error.localizedDescription)
            }
        }
    }

    func selectDatabase(_ database: String, for connectionID: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let connectionIndex = state.workspaces[workspaceIndex].connections.firstIndex(where: { $0.id == connectionID }) else { return }
        state.workspaces[workspaceIndex].connections[connectionIndex].database = database
        state.workspaces[workspaceIndex].queryTabs = state.workspaces[workspaceIndex].queryTabs.map { tab in
            var tab = tab
            if tab.connectionID == connectionID { tab.schema = nil }
            return tab
        }
        selectConnection(connectionID)
        save()
    }

    func schemas(for connectionID: UUID, database: String) -> [DatabaseSchema]? {
        schemasByDatabase[databaseKey(connectionID, database)]
    }

    func status(for connectionID: UUID, database: String) -> ConnectionStatus {
        databaseStatus[databaseKey(connectionID, database)] ?? .disconnected
    }

    func runQuery() {
        guard let query = selectedQuery, let connection = selectedConnection else {
            queryError = "Choose a database connection before running the query."
            return
        }
        executionTask?.cancel()
        isExecuting = true
        result = nil
        selectedResultRowID = nil
        queryError = nil
        executionTask = Task {
            do {
                let output: QueryResult
                switch connection.connectionKind {
                case .postgresql:
                    let password = try KeychainStore.password(for: connection.id) ?? ""
                    output = try await postgres.execute(
                        sql: query.sql,
                        connection: connection,
                        password: password,
                        searchPath: query.schema,
                        maximumRows: AppPreferences.resultRowLimit
                    )
                case .cloudflareD1:
                    output = try await d1.execute(
                        sql: query.sql,
                        connection: connection,
                        maximumRows: AppPreferences.resultRowLimit
                    )
                }
                guard !Task.isCancelled else { return }
                result = output
                lastExecutionDate = .now
                connectionStatus[connection.id] = .connected
            } catch is CancellationError {
                queryError = "Query cancelled."
            } catch {
                queryError = error.localizedDescription
                connectionStatus[connection.id] = .failed(error.localizedDescription)
            }
            isExecuting = false
        }
    }

    func cancelQuery() {
        executionTask?.cancel()
        executionTask = nil
        isExecuting = false
    }

    func queryTable(_ table: DatabaseTable, connectionID: UUID) {
        selectConnection(connectionID)
        let escapedSchema = table.schema.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedTable = table.name.replacingOccurrences(of: "\"", with: "\"\"")
        updateQueryText("SELECT *\nFROM \"\(escapedSchema)\".\"\(escapedTable)\"\nLIMIT 100;")
        selectSchema(table.schema)
        runQuery()
    }

    func discoverD1Databases(path: String, profile: String) {
        isDiscoveringD1 = true
        d1DiscoveryError = nil
        Task {
            do {
                discoveredD1Databases = try await d1.listDatabases(wranglerPath: path, profile: profile)
            } catch {
                discoveredD1Databases = []
                d1DiscoveryError = error.localizedDescription
            }
            isDiscoveringD1 = false
        }
    }

    func discoverLocalPostgres() {
        guard !isDiscoveringPostgres else { return }
        isDiscoveringPostgres = true
        Task {
            discoveredPostgres = await postgresDiscovery.discover()
            isDiscoveringPostgres = false
        }
    }

    private var selectedWorkspaceIndex: Int? {
        guard let id = state.selectedWorkspaceID else { return nil }
        return state.workspaces.firstIndex { $0.id == id }
    }

    private func databaseKey(_ connectionID: UUID, _ database: String) -> String {
        "\(connectionID):\(database)"
    }

    private func selectedQueryIndex(in workspaceIndex: Int) -> Int? {
        guard let id = state.workspaces[workspaceIndex].selectedQueryID else { return nil }
        return state.workspaces[workspaceIndex].queryTabs.firstIndex { $0.id == id }
    }

    private func ensureQuerySelection() {
        guard let index = selectedWorkspaceIndex else { return }
        if state.workspaces[index].queryTabs.isEmpty { state.workspaces[index].queryTabs = [QueryTab()] }
        if state.workspaces[index].selectedQueryID == nil {
            state.workspaces[index].selectedQueryID = state.workspaces[index].queryTabs.first?.id
        }
    }

    @discardableResult
    private func updateSelectedQueryDefault() -> Bool {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let queryIndex = selectedQueryIndex(in: workspaceIndex),
              let connection = selectedConnection else { return false }
        return updateQueryDefault(
            at: queryIndex,
            in: workspaceIndex,
            for: connection.connectionKind
        )
    }

    @discardableResult
    private func updateQueryDefault(
        at queryIndex: Int,
        in workspaceIndex: Int,
        for connectionKind: ConnectionKind
    ) -> Bool {
        let currentQuery = state.workspaces[workspaceIndex].queryTabs[queryIndex].sql
        guard AppPreferences.isBuiltInDefaultQuery(currentQuery) else { return false }
        let replacement = AppPreferences.defaultQueryText(for: connectionKind)
        guard currentQuery != replacement else { return false }
        state.workspaces[workspaceIndex].queryTabs[queryIndex].sql = replacement
        return true
    }

    private func clearExecution() {
        cancelQuery()
        result = nil
        selectedResultRowID = nil
        queryError = nil
        lastExecutionDate = nil
    }

    private func save() {
        try? persistence?.save(state)
    }
}
