import SwiftUI

struct WorkspaceView: View {
    @Bindable var store: AppStore
    @State private var selection: SidebarSelection?
    @AppStorage(AppPreferences.showInspectorKey) private var showInspector = true
    @State private var bottomTab = "Results"
    @State private var connectionEditorRequest: ConnectionEditorRequest?
    @State private var showingWorkspaceCreator = false
    @State private var workspaceName = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(
                store: store,
                selection: $selection,
                addConnection: { connectionEditorRequest = ConnectionEditorRequest(connection: nil) },
                editConnection: { connectionEditorRequest = ConnectionEditorRequest(connection: $0) }
            )
            .navigationSplitViewColumnWidth(min: 225, ideal: 270, max: 340)
        } detail: {
            ZStack {
                WorkspaceBackdrop()
                if let workspace = store.selectedWorkspace {
                    HSplitView {
                        VStack(spacing: 0) {
                            QueryTabBar(store: store, workspace: workspace)
                            QueryWorkspace(
                                store: store,
                                bottomTab: $bottomTab,
                                showInspector: $showInspector
                            )
                        }
                        if showInspector {
                            InspectorPanel(store: store)
                                .frame(minWidth: 235, idealWidth: 260, maxWidth: 310)
                        }
                    }
                } else {
                    ContentUnavailableView("No Workspace", systemImage: "square.grid.2x2", description: Text("Create a workspace to begin."))
                }
            }
        }
        .navigationTitle(store.selectedWorkspace?.name ?? "Selektos")
        .toolbar {
            ToolbarItem(placement: .principal) { WorkspaceMenu(store: store, createWorkspace: { showingWorkspaceCreator = true }) }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: store.runQuery) { Label("Run Query", systemImage: "play.fill") }
                    .disabled(store.selectedConnection == nil || store.isExecuting)
                    .keyboardShortcut(.return, modifiers: .command)
                Button(action: { showInspector.toggle() }) { Label("Inspector", systemImage: "sidebar.trailing") }
            }
        }
        .sheet(item: $connectionEditorRequest) { request in
            ConnectionEditor(store: store, connection: request.connection)
        }
        .alert("New Workspace", isPresented: $showingWorkspaceCreator) {
            TextField("Workspace name", text: $workspaceName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { store.addWorkspace(named: workspaceName); workspaceName = "" }
        } message: {
            Text("Workspaces keep connections and query tabs organized by project, client, or environment.")
        }
    }
}

private struct ConnectionEditorRequest: Identifiable {
    let id = UUID()
    let connection: DatabaseConnection?
}

private enum SidebarSelection: Hashable {
    case connection(UUID)
    case database(connection: UUID, name: String)
    case schema(connection: UUID, name: String)
    case table(connection: UUID, table: DatabaseTable)
}

private struct WorkspaceBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle().fill(.blue.opacity(0.12)).frame(width: 520, height: 520).blur(radius: 110).offset(x: -260, y: -290)
            Circle().fill(.purple.opacity(0.08)).frame(width: 440, height: 440).blur(radius: 120).offset(x: 390, y: 330)
        }
        .ignoresSafeArea()
    }
}

private struct WorkspaceMenu: View {
    @Bindable var store: AppStore
    let createWorkspace: () -> Void

    var body: some View {
        Menu {
            ForEach(store.state.workspaces) { workspace in
                Button {
                    store.selectWorkspace(workspace.id)
                } label: {
                    if workspace.id == store.state.selectedWorkspaceID {
                        Label(workspace.name, systemImage: "checkmark")
                    } else { Text(workspace.name) }
                }
            }
            Divider()
            Button("New Workspace…", action: createWorkspace)
            Button("Delete Workspace", role: .destructive, action: store.deleteSelectedWorkspace)
                .disabled(store.state.workspaces.count < 2)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(.blue)
                Text(store.selectedWorkspace?.name ?? "Workspace").fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
    }
}

private struct Sidebar: View {
    @Bindable var store: AppStore
    @Binding var selection: SidebarSelection?
    let addConnection: () -> Void
    let editConnection: (DatabaseConnection) -> Void
    @State private var search = ""
    @State private var expandedConnections: Set<UUID> = []
    @State private var expandedDatabases: Set<String> = []
    @State private var expandedSchemas: Set<String> = []
    @State private var expandedTables: Set<String> = []

    private var connections: [DatabaseConnection] {
        let all = store.selectedWorkspace?.connections ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.endpoint.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Connections") {
                    if connections.isEmpty {
                        Button(action: addConnection) { Label("Add Connection", systemImage: "plus.circle") }
                            .buttonStyle(.plain)
                    }
                    ForEach(connections) { connection in
                        Button {
                            toggleConnection(connection)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: expandedConnections.contains(connection.id) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)
                                ConnectionRow(connection: connection, status: store.connectionStatus[connection.id] ?? .disconnected)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(SidebarSelection.connection(connection.id))
                        .contextMenu {
                            Button("Refresh Schema") { store.loadSchema(for: connection) }
                            Button("Edit Connection…") { editConnection(connection) }
                            Divider()
                            Button("Delete Connection", role: .destructive) { store.deleteConnection(connection.id) }
                        }

                        if expandedConnections.contains(connection.id) {
                            switch store.connectionStatus[connection.id] {
                            case .loading:
                                HStack { ProgressView().controlSize(.small); Text("Loading database objects…") }
                                    .foregroundStyle(.secondary).padding(.leading, 22)
                            case .failed(let message):
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).lineLimit(3)
                                    Button("Try Again") { store.loadSchema(for: connection) }
                                }.padding(.leading, 22)
                            default:
                                let databases = store.databasesByConnection[connection.id] ?? []
                                if databases.isEmpty {
                                    Text("No databases found").foregroundStyle(.secondary).padding(.leading, 22)
                                }
                                ForEach(databases, id: \.self) { database in
                                    Button { toggleDatabase(connection, database) } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: expandedDatabases.contains(databaseKey(connection.id, database)) ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 8, weight: .semibold)).frame(width: 10)
                                            Label(database, systemImage: "cylinder")
                                                .fontWeight(database == connection.database ? .semibold : .regular)
                                            Spacer()
                                            if database == connection.database {
                                                Text("ACTIVE").font(.system(size: 7, weight: .bold)).foregroundStyle(.green)
                                            }
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain).padding(.leading, 18)

                                    if expandedDatabases.contains(databaseKey(connection.id, database)) {
                                        switch store.status(for: connection.id, database: database) {
                                        case .loading:
                                            HStack { ProgressView().controlSize(.small); Text("Loading schemas…") }
                                                .foregroundStyle(.secondary).padding(.leading, 40)
                                        case .failed(let message):
                                            VStack(alignment: .leading) {
                                                Text(message).foregroundStyle(.red).lineLimit(3)
                                                Button("Try Again") { store.loadSchema(for: connection, database: database) }
                                            }.padding(.leading, 40)
                                        default:
                                            ForEach(store.schemas(for: connection.id, database: database) ?? []) { schema in
                                                Button { toggleSchema(connection.id, database, schema.name) } label: {
                                                    HStack(spacing: 6) {
                                                        Image(systemName: expandedSchemas.contains(schemaKey(connection.id, database, schema.name)) ? "chevron.down" : "chevron.right")
                                                            .font(.system(size: 8, weight: .semibold)).frame(width: 10)
                                                        Label(schema.name, systemImage: isSystemSchema(schema.name) ? "gearshape.2" : "folder")
                                                            .foregroundStyle(isSystemSchema(schema.name) ? .secondary : .primary)
                                                        Spacer()
                                                        Text(String(schema.tables.count)).foregroundStyle(.tertiary)
                                                    }.contentShape(Rectangle())
                                                }.buttonStyle(.plain).padding(.leading, 36)

                                                if expandedSchemas.contains(schemaKey(connection.id, database, schema.name)) {
                                                    if schema.tables.isEmpty {
                                                        Text("No tables or views").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 58)
                                                    }
                                                    ForEach(schema.tables) { table in
                                                        Button { toggleTable(connection.id, database, table) } label: {
                                                            HStack(spacing: 6) {
                                                                Image(systemName: expandedTables.contains(tableKey(connection.id, database, table)) ? "chevron.down" : "chevron.right")
                                                                    .font(.system(size: 8, weight: .semibold)).frame(width: 10)
                                                                Label(table.name, systemImage: "tablecells")
                                                                Spacer()
                                                                Text(String(table.columns.count)).foregroundStyle(.tertiary)
                                                            }.contentShape(Rectangle())
                                                        }
                                                        .buttonStyle(.plain).padding(.leading, 54)
                                                        .contextMenu { Button("Open in New Query") {
                                                            store.selectDatabase(database, for: connection.id)
                                                            store.queryTable(table, connectionID: connection.id)
                                                        } }

                                                        if expandedTables.contains(tableKey(connection.id, database, table)) {
                                                            ForEach(table.columns) { column in
                                                                ColumnRow(column: column).padding(.leading, 76)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Filter connections")
            .onChange(of: selection) { _, value in
                if case .connection(let id) = value { store.selectConnection(id) }
                if case .table(let id, _) = value { store.selectConnection(id) }
            }
            Divider()
            HStack {
                Button(action: addConnection) { Image(systemName: "plus") }.help("New Connection")
                Spacer()
                if let connection = store.selectedConnection {
                    Button { store.loadSchema(for: connection) } label: { Image(systemName: "arrow.clockwise") }.help("Refresh Schema")
                }
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 38)
        }
    }

    private func toggleConnection(_ connection: DatabaseConnection) {
        if expandedConnections.contains(connection.id) {
            expandedConnections.remove(connection.id)
        } else {
            expandedConnections.insert(connection.id)
            selection = .connection(connection.id)
            store.selectConnection(connection.id)
            if store.databasesByConnection[connection.id] == nil { store.loadDatabases(for: connection) }
        }
    }

    private func databaseKey(_ connectionID: UUID, _ database: String) -> String {
        "\(connectionID):\(database)"
    }

    private func schemaKey(_ connectionID: UUID, _ database: String, _ schema: String) -> String {
        "\(connectionID):\(database):\(schema)"
    }

    private func tableKey(_ connectionID: UUID, _ database: String, _ table: DatabaseTable) -> String {
        "\(connectionID):\(database):\(table.id)"
    }

    private func toggleDatabase(_ connection: DatabaseConnection, _ database: String) {
        let key = databaseKey(connection.id, database)
        if expandedDatabases.contains(key) {
            expandedDatabases.remove(key)
        } else {
            expandedDatabases.insert(key)
            selection = .database(connection: connection.id, name: database)
            store.selectDatabase(database, for: connection.id)
            if store.schemas(for: connection.id, database: database) == nil {
                store.loadSchema(for: connection, database: database)
            }
        }
    }

    private func toggleSchema(_ connectionID: UUID, _ database: String, _ schema: String) {
        let key = schemaKey(connectionID, database, schema)
        if expandedSchemas.contains(key) { expandedSchemas.remove(key) }
        else { expandedSchemas.insert(key) }
    }

    private func toggleTable(_ connectionID: UUID, _ database: String, _ table: DatabaseTable) {
        let key = tableKey(connectionID, database, table)
        if expandedTables.contains(key) { expandedTables.remove(key) }
        else { expandedTables.insert(key) }
    }

    private func isSystemSchema(_ name: String) -> Bool {
        name == "information_schema" || name.hasPrefix("pg_")
    }
}

private struct ColumnRow: View {
    let column: DatabaseColumn

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: column.isPrimaryKey ? "key.fill" : "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 9))
                .foregroundStyle(column.isPrimaryKey ? Color.yellow : Color.secondary.opacity(0.5))
                .frame(width: 12)
            Text(column.name).lineLimit(1)
            Spacer(minLength: 4)
            Text(column.dataType.lowercased())
                .foregroundStyle(.tertiary).lineLimit(1)
            if !column.isNullable {
                Text("NN").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .help(column.isNullable ? column.dataType : "\(column.dataType), not null")
    }
}

private struct ConnectionRow: View {
    let connection: DatabaseConnection
    let status: ConnectionStatus
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connection.connectionKind == .cloudflareD1 ? "cloud.fill" : "cylinder.split.1x2.fill").foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(connection.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !connection.labels.isEmpty {
                        ConnectionLabelsBadge(labels: connection.labels)
                    }
                }
                Text("\(connection.engineName) · \(connection.endpoint)").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .font(.system(size: 12))
    }
    private var statusColor: Color {
        switch status { case .connected: .green; case .loading: .orange; case .failed: .red; case .disconnected: .blue }
    }
}

private struct ConnectionLabelsBadge: View {
    let labels: [ConnectionLabel]

    private var text: String {
        labels.map(\.name).joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 7))
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
        .help(text)
    }
}

private struct QueryTabBar: View {
    @Bindable var store: AppStore
    let workspace: Workspace
    @State private var queryToRename: QueryTab?
    @State private var queryName = ""

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(workspace.queryTabs) { tab in
                        let isSelected = workspace.selectedQueryID == tab.id
                        let tabWeight: Font.Weight = isSelected ? .medium : .regular
                        let tabColor: Color = isSelected ? .primary : .secondary
                        Button { store.selectQuery(tab.id) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text")
                                Text(tab.title)
                                    .lineLimit(1)
                                    .help("Control-click to rename")
                                Button { store.closeQuery(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }
                                    .buttonStyle(.plain).disabled(workspace.queryTabs.count == 1)
                            }
                            .font(.system(size: 12, weight: tabWeight))
                            .foregroundStyle(tabColor)
                            .padding(.horizontal, 11).frame(height: 34)
                            .liquidGlass(isActive: isSelected, interactive: true, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename…") { beginRenaming(tab) }
                            Divider()
                            Button("Close Query") { store.closeQuery(tab.id) }
                                .disabled(workspace.queryTabs.count == 1)
                        }
                    }
                }.padding(.horizontal, 7)
            }
            Spacer(minLength: 4)
            Button { store.addQuery() } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 7)
        }
        .frame(height: 42).background(.ultraThinMaterial.opacity(0.72)).overlay(alignment: .bottom) { Divider() }
        .alert("Rename Query", isPresented: Binding(
            get: { queryToRename != nil },
            set: { if !$0 { queryToRename = nil } }
        )) {
            TextField("Query name", text: $queryName)
            Button("Cancel", role: .cancel) { queryToRename = nil }
            Button("Rename") {
                if let queryToRename {
                    store.renameQuery(queryToRename.id, to: queryName)
                }
                queryToRename = nil
            }
            .disabled(queryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a name for this query tab.")
        }
    }

    private func beginRenaming(_ query: QueryTab) {
        queryName = query.title
        queryToRename = query
    }
}

private struct QueryWorkspace: View {
    @Bindable var store: AppStore
    @Binding var bottomTab: String
    @Binding var showInspector: Bool
    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                EditorToolbar(store: store)
                if let query = store.selectedQuery {
                    SQLEditor(
                        text: Binding(get: { query.sql }, set: store.updateQueryText),
                        completionCatalog: SQLCompletionCatalog(
                            schemas: store.completionSchemas,
                            focusedSchema: query.schema
                        )
                    )
                    .id(query.id)
                } else { ContentUnavailableView("No Query", systemImage: "doc.text") }
            }.frame(minHeight: 230, idealHeight: 350)
            ResultsArea(
                store: store,
                selectedTab: $bottomTab,
                showInspector: $showInspector
            )
            .frame(minHeight: 230, idealHeight: 390)
        }
    }
}

private struct EditorToolbar: View {
    @Bindable var store: AppStore
    var body: some View {
        HStack(spacing: 10) {
            Button(action: store.runQuery) { Label("Run", systemImage: "play.fill") }
                .liquidGlassButton(prominent: true).controlSize(.small)
                .disabled(store.selectedConnection == nil || store.isExecuting)
            Button(action: store.cancelQuery) { Image(systemName: "stop.fill") }
                .buttonStyle(.bordered).controlSize(.small).disabled(!store.isExecuting)
            Divider().frame(height: 15)
            if store.isExecuting { ProgressView().controlSize(.small); Text("Running…").foregroundStyle(.secondary) }
            Spacer()
            if let workspace = store.selectedWorkspace, !workspace.connections.isEmpty {
                Picker("Connection", selection: Binding(get: { store.selectedConnection?.id }, set: { if let id = $0 { store.selectConnection(id) } })) {
                    ForEach(workspace.connections) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden().frame(maxWidth: 180)
                if let connection = store.selectedConnection, connection.connectionKind == .postgresql {
                    databasePicker(for: connection)
                    schemaPicker
                }
            } else { Label("No connection", systemImage: "cylinder").foregroundStyle(.secondary) }
        }
        .font(.system(size: 11)).padding(.horizontal, 12).frame(height: 40)
        .background(.ultraThinMaterial.opacity(0.68)).overlay(alignment: .bottom) { Divider() }
        .task(id: store.selectedConnection?.id) {
            if let connection = store.selectedConnection { store.ensureMetadataLoaded(for: connection) }
        }
    }

    @ViewBuilder
    private func databasePicker(for connection: DatabaseConnection) -> some View {
        let databases = store.databasesByConnection[connection.id] ?? [connection.database]
        Picker("Database", selection: Binding(
            get: { connection.database },
            set: { store.selectDatabase($0, for: connection.id) }
        )) {
            ForEach(databases.contains(connection.database) ? databases : databases + [connection.database], id: \.self) {
                Text($0).tag($0)
            }
        }
        .labelsHidden().frame(maxWidth: 150)
        .help("Database queries run against")
    }

    @ViewBuilder
    private var schemaPicker: some View {
        Picker("Schema", selection: Binding(
            get: { store.selectedQuery?.schema },
            set: store.selectSchema
        )) {
            Text("All schemas").tag(String?.none)
            ForEach(store.availableSchemas, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .labelsHidden().frame(maxWidth: 160)
        .disabled(store.selectedQuery == nil)
        .help("Focus a schema: unqualified names resolve there first, then public")
    }
}

private struct ResultsArea: View {
    @Bindable var store: AppStore
    @Binding var selectedTab: String
    @Binding var showInspector: Bool
    private let tabs = ["Results", "Messages"]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(tabs, id: \.self) { tab in
                    let tabWeight: Font.Weight = selectedTab == tab ? .semibold : .regular
                    Button(tab) { selectedTab = tab }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: tabWeight))
                        .overlay(alignment: .bottom) { if selectedTab == tab { Capsule().fill(.blue).frame(height: 2).offset(y: 10) } }
                }
                Spacer()
                if let result = store.result { Text("\(result.rows.count) rows in \(result.durationText)").foregroundStyle(.secondary) }
            }
            .font(.system(size: 11)).padding(.horizontal, 13).frame(height: 40)
            .background(.ultraThinMaterial.opacity(0.72)).overlay(alignment: .bottom) { Divider() }
            if selectedTab == "Messages" { MessageView(store: store) }
            else if let result = store.result {
                DynamicResultsGrid(
                    result: result,
                    selectedRowID: store.selectedResultRowID
                ) { rowID in
                    store.selectResultRow(rowID)
                    showInspector = true
                }
                .id(result.id)
            }
            else if store.isExecuting { ProgressView("Executing query…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ContentUnavailableView("No Results", systemImage: "tablecells", description: Text("Run a query with Command-Return.")) }
        }
        .onChange(of: store.queryError) { _, error in if error != nil { selectedTab = "Messages" } }
    }
}

private struct MessageView: View {
    @Bindable var store: AppStore
    private var iconName: String {
        if store.queryError == nil { return "checkmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }
    private var message: String {
        if let error = store.queryError { return error }
        if let result = store.result {
            return "\(result.command) completed successfully. \(result.rows.count) rows returned in \(result.durationText)."
        }
        return "Messages from query execution appear here."
    }
    private var iconColor: Color {
        if store.queryError == nil { return .green }
        return .red
    }
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(message)
                    .textSelection(.enabled)
                Spacer()
            }.padding(18)
        }
    }
}

private struct DynamicResultsGrid: View {
    let result: QueryResult
    let selectedRowID: Int?
    let selectRow: (Int) -> Void
    @StateObject private var layout: ResultGridLayout

    init(
        result: QueryResult,
        selectedRowID: Int?,
        selectRow: @escaping (Int) -> Void
    ) {
        self.result = result
        self.selectedRowID = selectedRowID
        self.selectRow = selectRow
        _layout = StateObject(wrappedValue: ResultGridLayout(result: result))
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(result.rows) { row in
                        ResultGridRow(
                            row: row,
                            columnWidths: layout.columnWidths,
                            isSelected: row.id == selectedRowID,
                            select: { selectRow(row.id) }
                        )
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("").frame(width: 55)
                        ForEach(Array(result.columns.enumerated()), id: \.offset) { index, column in
                            Text(column)
                                .fontWeight(.semibold)
                                .frame(width: layout.columnWidths[index], alignment: .leading)
                                .padding(.horizontal, 9)
                        }
                    }.frame(height: 30).background(.bar).overlay(alignment: .bottom) { Divider() }
                }
            }.font(.system(size: 12))
        }
        .defaultScrollAnchor(.topLeading)
    }
}

private struct ResultGridRow: View {
    let row: QueryResultRow
    let columnWidths: [CGFloat]
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(String(row.id + 1))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 45, alignment: .trailing)
                .padding(.trailing, 10)
            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                ResultValueCell(value: value, width: columnWidths[index])
            }
        }
        .frame(height: 29)
        .background(rowBackground)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded(select))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        if row.id.isMultiple(of: 2) { return Color.primary.opacity(0.025) }
        return .clear
    }
}

private final class ResultGridLayout: ObservableObject {
    let columnWidths: [CGFloat]

    init(result: QueryResult) {
        let valueColumnCount = result.rows.reduce(0) { max($0, $1.values.count) }
        let columnCount = max(result.columns.count, valueColumnCount)
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let valueFont = NSFont.systemFont(ofSize: 12)
        var widths = Array(repeating: CGFloat.zero, count: columnCount)

        for (index, column) in result.columns.enumerated() {
            widths[index] = Self.textWidth(column, font: headerFont)
        }
        for row in result.rows {
            for (index, value) in row.values.enumerated() {
                widths[index] = max(widths[index], Self.textWidth(value, font: valueFont))
            }
        }

        columnWidths = widths
    }

    private static func textWidth(_ value: String, font: NSFont) -> CGFloat {
        (value as NSString)
            .size(withAttributes: [.font: font])
            .width
            .rounded(.up)
    }
}

private struct ResultValueCell: View {
    let value: String
    let width: CGFloat

    var body: some View {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 9)
            .foregroundStyle(valueColor)
    }

    private var valueColor: Color {
        if value == "NULL" { return Color.secondary.opacity(0.55) }
        return .primary
    }
}

private struct InspectorPanel: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let row = store.selectedResultRow {
                    Text("Row \(row.id + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    InspectorSection(title: "SELECTED ROW") {
                        if let row = store.selectedResultRow, let result = store.result {
                            ForEach(Array(fields(for: row, in: result).enumerated()), id: \.offset) { _, field in
                                InspectorValueRow(column: field.column, value: field.value)
                            }
                        } else if store.result != nil {
                            InspectorPlaceholder(
                                icon: "cursorarrow.click.2",
                                text: "Click a result row to inspect the record."
                            )
                        } else {
                            InspectorPlaceholder(
                                icon: "tablecells",
                                text: "Run a query, then select a row."
                            )
                        }
                    }
                    InspectorSection(title: "EXECUTION") {
                        DetailRow(label: "Duration", value: store.result?.durationText ?? "—")
                        DetailRow(label: "Rows", value: store.result.map { String($0.rows.count) } ?? "—")
                        DetailRow(label: "Command", value: store.result?.command ?? "—")
                    }
                    InspectorSection(title: "CONNECTION") {
                        DetailRow(label: "Name", value: store.selectedConnection?.name ?? "None")
                        DetailRow(label: "Provider", value: store.selectedConnection?.engineName ?? "—")
                        DetailRow(label: "Database", value: store.selectedConnection?.endpoint ?? "—")
                        if store.selectedConnection?.connectionKind == .postgresql {
                            DetailRow(label: "Host", value: store.selectedConnection?.host ?? "—")
                            DetailRow(label: "TLS", value: store.selectedConnection?.tlsMode.title ?? "—")
                        } else {
                            DetailRow(label: "Mode", value: "Wrangler remote")
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.ultraThinMaterial.opacity(0.76))
        .liquidGlass(in: Rectangle())
    }

    private func fields(
        for row: QueryResultRow,
        in result: QueryResult
    ) -> [(column: String, value: String)] {
        let count = max(result.columns.count, row.values.count)
        return (0..<count).map { index in
            let column = result.columns.indices.contains(index)
                ? result.columns[index]
                : "Column \(index + 1)"
            let value = row.values.indices.contains(index) ? row.values[index] : "—"
            return (column, value)
        }
    }
}

private struct InspectorValueRow: View {
    let column: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(column)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(value == "NULL" ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }
}

private struct InspectorPlaceholder: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct ConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore
    let connection: DatabaseConnection?
    @State private var draft: ConnectionDraft
    @State private var error: String?
    @State private var didStartDiscovery = false

    init(store: AppStore, connection: DatabaseConnection?) {
        self.store = store
        self.connection = connection
        if let connection {
            _draft = State(initialValue: ConnectionDraft(connection: connection, password: store.password(for: connection.id)))
        } else {
            _draft = State(initialValue: ConnectionDraft())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Provider", selection: $draft.kind) {
                    ForEach(ConnectionKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                TextField("Name", text: $draft.name, prompt: Text("Local PostgreSQL"))
                if draft.kind == .postgresql {
                    TextField("Host", text: $draft.host)
                    TextField("Port", text: portBinding)
                    TextField("Database", text: $draft.database)
                    TextField("Username", text: $draft.username)
                    SecureField("Password", text: $draft.password)
                    Picker("TLS", selection: $draft.tlsMode) { ForEach(TLSMode.allCases) { Text($0.title).tag($0) } }
                    if connection == nil {
                        PostgresDiscoveryNotice(
                            discoveries: store.discoveredPostgres,
                            isDiscovering: store.isDiscoveringPostgres,
                            use: useDiscoveredPostgres,
                            refresh: store.discoverLocalPostgres
                        )
                    }
                } else {
                    TextField("Wrangler executable", text: $draft.wranglerPath, prompt: Text("wrangler (auto-detected)"))
                    TextField("Auth profile", text: $draft.wranglerProfile, prompt: Text("Default authenticated profile"))
                    if connection == nil {
                        HStack {
                            Picker("D1 database", selection: $draft.d1Database) {
                                if draft.d1Database.isEmpty { Text("Choose a database").tag("") }
                                ForEach(store.discoveredD1Databases) { database in Text(database.name).tag(database.name) }
                            }
                            Button("Discover") { store.discoverD1Databases(path: draft.wranglerPath, profile: draft.wranglerProfile) }
                                .disabled(store.isDiscoveringD1 || draft.wranglerPath.isEmpty)
                            if store.isDiscoveringD1 { ProgressView().controlSize(.small) }
                        }
                        if let error = store.d1DiscoveryError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    } else {
                        TextField("D1 database", text: $draft.d1Database)
                    }
                    Text("Uses your existing Wrangler login. Query execution targets the remote D1 database.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Labels", text: $draft.labels, prompt: Text("PROD, READ ONLY"))
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped).padding()
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try store.saveConnection(draft, editing: connection?.id); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!isValid)
            }.padding()
        }.frame(width: 540, height: 570).navigationTitle(connection == nil ? "New Connection" : "Edit Connection")
            .onAppear {
                guard connection == nil, !didStartDiscovery else { return }
                didStartDiscovery = true
                runDiscovery(for: draft.kind)
            }
            .onChange(of: draft.kind) { _, kind in
                if connection == nil { runDiscovery(for: kind) }
            }
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { String(draft.port) },
            set: { value in
                let digits = value.filter(\.isNumber)
                if let port = Int(digits), (1...65_535).contains(port) {
                    draft.port = port
                }
            }
        )
    }

    private func runDiscovery(for kind: ConnectionKind) {
        switch kind {
        case .postgresql:
            store.discoverLocalPostgres()
        case .cloudflareD1:
            store.discoverD1Databases(path: draft.wranglerPath, profile: draft.wranglerProfile)
        }
    }

    private func useDiscoveredPostgres(_ discovery: DiscoveredPostgres) {
        draft.host = discovery.host
        draft.port = discovery.port
        if draft.name.isEmpty { draft.name = "Local PostgreSQL" }
        if draft.labels.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.labels = "DEV" }
    }

    private var isValid: Bool {
        guard !draft.name.isEmpty else { return false }
        switch draft.kind {
        case .postgresql: return !draft.host.isEmpty && !draft.database.isEmpty && !draft.username.isEmpty
        case .cloudflareD1: return !draft.wranglerPath.isEmpty && !draft.d1Database.isEmpty
        }
    }
}

private struct PostgresDiscoveryNotice: View {
    let discoveries: [DiscoveredPostgres]
    let isDiscovering: Bool
    let use: (DiscoveredPostgres) -> Void
    let refresh: () -> Void

    var body: some View {
        if isDiscovering {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for PostgreSQL on this Mac…")
                    .foregroundStyle(.secondary)
            }
        } else if discoveries.isEmpty {
            HStack {
                Label("No local PostgreSQL server found on common ports.", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Scan Again", action: refresh)
            }
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("PostgreSQL appears to be running locally", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                ForEach(discoveries) { discovery in
                    HStack {
                        Text("Found a PostgreSQL server on \(discovery.host):\(discovery.port). Use it?")
                            .font(.caption)
                        Spacer()
                        Button("Use Connection") { use(discovery) }
                    }
                }
            }
            .padding(10)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.green.opacity(0.2)) }
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).tracking(0.5); content } }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1).truncationMode(.middle) }.font(.system(size: 12)) }
}

private extension View {
    @ViewBuilder func liquidGlass<S: Shape>(isActive: Bool = true, interactive: Bool = false, in shape: S) -> some View {
        if isActive {
            if #available(macOS 26.0, *) {
                if interactive {
                    glassEffect(.regular.interactive(), in: shape)
                } else {
                    glassEffect(.regular, in: shape)
                }
            }
            else { background(.ultraThinMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.5)) }
        } else { self }
    }
    @ViewBuilder func liquidGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        }
        else if prominent { buttonStyle(.borderedProminent) }
        else { buttonStyle(.bordered) }
    }
}
