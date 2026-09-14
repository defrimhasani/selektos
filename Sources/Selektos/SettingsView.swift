import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    @AppStorage(AppPreferences.selectedSettingsPaneKey) private var selectedPane = SettingsDestination.general.rawValue

    private var selection: Binding<SettingsDestination?> {
        Binding(
            get: { SettingsDestination(rawValue: selectedPane) ?? .general },
            set: { selectedPane = ($0 ?? .general).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsDestination.allCases, selection: selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(Optional(destination))
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            switch SettingsDestination(rawValue: selectedPane) ?? .general {
            case .general:
                GeneralSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .workspaces:
                WorkspaceSettingsView(store: store)
            case .connections:
                ConnectionSettingsView(store: store)
            case .mcp:
                MCPSettingsView(store: store)
            case .about:
                AboutSettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 780, height: 540)
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case appearance
    case workspaces
    case connections
    case mcp
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .workspaces: "Workspaces"
        case .connections: "Connections"
        case .mcp: "MCP Server"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .workspaces: "square.grid.2x2"
        case .connections: "cylinder"
        case .mcp: "point.3.connected.trianglepath.dotted"
        case .about: "info.circle"
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppPreferences.restoreLastWorkspaceKey) private var restoreLastWorkspace = true
    @AppStorage(AppPreferences.automaticallyLoadMetadataKey) private var automaticallyLoadMetadata = true
    @AppStorage(AppPreferences.resultRowLimitKey) private var resultRowLimit = 10_000
    @AppStorage(AppPreferences.defaultQueryKey) private var defaultQuery = AppPreferences.defaultQuery

    var body: some View {
        SettingsPage(title: "General", subtitle: "Control startup, discovery, and query defaults.") {
            SettingsCard(title: "Startup") {
                Toggle("Restore last workspace", isOn: $restoreLastWorkspace)
                SettingsHint("When disabled, Selektos opens the first workspace.")
            }

            SettingsCard(title: "Queries") {
                Picker("Maximum displayed rows", selection: $resultRowLimit) {
                    ForEach(AppPreferences.rowLimitOptions, id: \.self) { limit in
                        Text(limit.formatted()).tag(limit)
                    }
                }
                SettingsHint("Add LIMIT to SQL when the database should avoid producing extra rows.")

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Default text for new query tabs")
                    TextEditor(text: $defaultQuery)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(height: 72)
                        .background(.background, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(.separator.opacity(0.65))
                        }
                    SettingsHint("Blank text falls back to \(AppPreferences.defaultQuery).")
                }
            }

            SettingsCard(title: "Database metadata") {
                Toggle("Load databases and schemas automatically", isOn: $automaticallyLoadMetadata)
                SettingsHint("Turn off for large or restricted servers. Sidebar refresh remains available.")
            }

            StorageLocationView()
        }
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(AppPreferences.appearanceKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppPreferences.editorFontSizeKey) private var editorFontSize = 14.0
    @AppStorage(AppPreferences.showLineNumbersKey) private var showLineNumbers = true
    @AppStorage(AppPreferences.showInspectorKey) private var showInspector = true

    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Choose how Selektos and its editor look.") {
            SettingsCard(title: "App") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsCard(title: "Editor") {
                HStack {
                    Text("Font size")
                    Slider(value: $editorFontSize, in: 11...22, step: 1)
                    Text("\(Int(editorFontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                Toggle("Show line numbers", isOn: $showLineNumbers)
                Toggle("Show inspector", isOn: $showInspector)

                EditorPreview(fontSize: editorFontSize, showLineNumbers: showLineNumbers)
            }
        }
    }
}

private struct EditorPreview: View {
    let fontSize: Double
    let showLineNumbers: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showLineNumbers {
                Text("1\n2")
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            }
            Text("SELECT *\nFROM public.users;")
                .foregroundStyle(.primary)
            Spacer()
        }
        .font(.system(size: fontSize, design: .monospaced))
        .lineSpacing(4)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator.opacity(0.65))
        }
    }
}

private struct WorkspaceSettingsView: View {
    @Bindable var store: AppStore
    @State private var newWorkspaceName = ""
    @State private var renameWorkspace: Workspace?
    @State private var renameText = ""
    @State private var deleteWorkspace: Workspace?

    var body: some View {
        SettingsPage(title: "Workspaces", subtitle: "Organize query tabs and connections by project or environment.") {
            SettingsCard(title: "Your workspaces") {
                ForEach(Array(store.state.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    WorkspaceSettingsRow(
                        workspace: workspace,
                        isSelected: workspace.id == store.state.selectedWorkspaceID,
                        select: { store.selectWorkspace(workspace.id) },
                        rename: {
                            renameWorkspace = workspace
                            renameText = workspace.name
                        },
                        delete: { deleteWorkspace = workspace },
                        canDelete: store.state.workspaces.count > 1
                    )
                    if index < store.state.workspaces.count - 1 { Divider() }
                }
            }

            SettingsCard(title: "New workspace") {
                HStack {
                    TextField("Workspace name", text: $newWorkspaceName)
                        .onSubmit(addWorkspace)
                    Button("Add", action: addWorkspace)
                        .disabled(newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Rename Workspace", isPresented: Binding(
            get: { renameWorkspace != nil },
            set: { if !$0 { renameWorkspace = nil } }
        )) {
            TextField("Workspace name", text: $renameText)
            Button("Cancel", role: .cancel) { renameWorkspace = nil }
            Button("Rename") {
                if let workspace = renameWorkspace {
                    store.renameWorkspace(workspace.id, to: renameText)
                }
                renameWorkspace = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Connections and query tabs stay in this workspace.")
        }
        .alert("Delete Workspace?", isPresented: Binding(
            get: { deleteWorkspace != nil },
            set: { if !$0 { deleteWorkspace = nil } }
        ), presenting: deleteWorkspace) { workspace in
            Button("Cancel", role: .cancel) { deleteWorkspace = nil }
            Button("Delete", role: .destructive) {
                store.deleteWorkspace(workspace.id)
                deleteWorkspace = nil
            }
        } message: { workspace in
            Text("“\(workspace.name)” and its query tabs will be deleted. Stored passwords for its connections will also be removed from Keychain.")
        }
    }

    private func addWorkspace() {
        let name = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.addWorkspace(named: name)
        newWorkspaceName = ""
    }
}

private struct WorkspaceSettingsRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let select: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let canDelete: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 17))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(workspace.name).fontWeight(.medium)
                    if isSelected {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(workspace.connections.count) connections · \(workspace.queryTabs.count) query tabs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isSelected {
                Button("Open", action: select)
                    .controlSize(.small)
            }

            Menu {
                Button("Rename…", action: rename)
                Button("Delete…", role: .destructive, action: delete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 4)
    }
}

private struct ConnectionSettingsView: View {
    @Bindable var store: AppStore
    @State private var editorRequest: SettingsConnectionEditorRequest?
    @State private var deleteConnection: DatabaseConnection?

    var body: some View {
        SettingsPage(title: "Connections", subtitle: "Manage database endpoints and Keychain-backed credentials.") {
            SettingsCard(title: "Workspace") {
                Picker("Active workspace", selection: Binding(
                    get: { store.state.selectedWorkspaceID },
                    set: { if let id = $0 { store.selectWorkspace(id) } }
                )) {
                    ForEach(store.state.workspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace.id))
                    }
                }
            }

            SettingsCard(title: "Saved connections") {
                if let workspace = store.selectedWorkspace, workspace.connections.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "cylinder",
                        description: Text("Add PostgreSQL or Cloudflare D1.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 130)
                } else if let workspace = store.selectedWorkspace {
                    ForEach(Array(workspace.connections.enumerated()), id: \.element.id) { index, connection in
                        ConnectionSettingsRow(
                            connection: connection,
                            edit: { editorRequest = SettingsConnectionEditorRequest(connection: connection) },
                            delete: { deleteConnection = connection }
                        )
                        if index < workspace.connections.count - 1 { Divider() }
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button {
                        editorRequest = SettingsConnectionEditorRequest(connection: nil)
                    } label: {
                        Label("Add Connection", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            ConnectionEditor(store: store, connection: request.connection)
        }
        .alert("Delete Connection?", isPresented: Binding(
            get: { deleteConnection != nil },
            set: { if !$0 { deleteConnection = nil } }
        ), presenting: deleteConnection) { connection in
            Button("Cancel", role: .cancel) { deleteConnection = nil }
            Button("Delete", role: .destructive) {
                store.deleteConnection(connection.id)
                deleteConnection = nil
            }
        } message: { connection in
            Text("“\(connection.name)” will be removed from this workspace. Its password will be deleted from Keychain.")
        }
    }
}

private struct SettingsConnectionEditorRequest: Identifiable {
    let id = UUID()
    let connection: DatabaseConnection?
}

private struct ConnectionSettingsRow: View {
    let connection: DatabaseConnection
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.connectionKind == .postgresql ? "cylinder.fill" : "cloud.fill")
                .font(.system(size: 17))
                .foregroundStyle(connection.connectionKind == .postgresql ? .blue : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(connection.name).fontWeight(.medium)
                    Text(connection.engineName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(connection.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
            Button("Edit", action: edit).controlSize(.small)
            Button(action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Delete connection")
        }
        .padding(.vertical, 4)
    }
}

private struct MCPSettingsView: View {
    @Bindable var store: AppStore
    @AppStorage(
        MCPPreferences.enabledKey,
        store: MCPPreferences.defaults
    ) private var isEnabled = false
    @AppStorage(
        MCPPreferences.readOnlyKey,
        store: MCPPreferences.defaults
    ) private var isReadOnly = true
    @AppStorage(
        MCPPreferences.maximumRowsKey,
        store: MCPPreferences.defaults
    ) private var maximumRows = MCPPreferences.defaultMaximumRows
    @State private var copyStatus: String?

    private var clientConfiguration: String {
        MCPPreferences.clientConfigurationJSON()
    }

    private var exposedConnections: [MCPSettingsConnection] {
        store.state.workspaces.flatMap { workspace in
            workspace.connections.map {
                MCPSettingsConnection(workspace: workspace.name, connection: $0)
            }
        }
    }

    var body: some View {
        SettingsPage(
            title: "MCP Server",
            subtitle: "Let local AI agents query connections saved in Selektos."
        ) {
            SettingsCard(title: "Access") {
                Toggle("Enable MCP server", isOn: $isEnabled)
                SettingsHint(
                    "The stdio server runs only when an MCP client launches it. Disabling access also rejects calls from an existing session."
                )

                Divider()

                Toggle("Read-only access", isOn: $isReadOnly)
                SettingsHint(
                    "Recommended. Selektos rejects mutating SQL and also runs PostgreSQL queries inside read-only transactions. Restart the MCP client after changing this setting."
                )

                if !isReadOnly {
                    Label(
                        "Read/write mode allows agents to modify or delete database data using your saved credentials.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            SettingsCard(title: "Query results") {
                Picker("Maximum rows returned per tool call", selection: $maximumRows) {
                    ForEach(MCPPreferences.rowLimitOptions, id: \.self) { limit in
                        Text(limit.formatted()).tag(limit)
                    }
                }
                SettingsHint(
                    "Agents can request fewer rows, but cannot exceed this limit. Restart the MCP client after changing this setting."
                )
            }

            SettingsCard(title: "Client configuration") {
                Text(clientConfiguration)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.separator.opacity(0.65))
                    }

                HStack {
                    SettingsHint(
                        "Add this server entry to your agent's MCP configuration. Restart the MCP client after changing access settings or connections."
                    )
                    Spacer()
                    if let copyStatus {
                        Text(copyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Copy Configuration", action: copyConfiguration)
                }
            }

            SettingsCard(title: "Exposed connections") {
                if exposedConnections.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "cylinder",
                        description: Text("Add a connection before starting an MCP client.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(Array(exposedConnections.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: item.connection.connectionKind == .postgresql
                                ? "cylinder.fill"
                                : "cloud.fill")
                                .foregroundStyle(item.connection.connectionKind == .postgresql
                                    ? .blue
                                    : .orange)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.connection.name)
                                    .fontWeight(.medium)
                                Text("\(item.workspace) · \(item.connection.endpoint)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(item.toolNames, id: \.self) { toolName in
                                    Text(toolName)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        if index < exposedConnections.count - 1 {
                            Divider()
                        }
                    }
                    SettingsHint(
                        "Each saved connection exposes tools to list tables, describe a table, preview rows, and run SQL. Passwords remain in macOS Keychain and are never included in tool metadata."
                    )
                }
            }
        }
    }

    private func copyConfiguration() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copyStatus = pasteboard.setString(clientConfiguration, forType: .string)
            ? "Copied"
            : "Copy failed"
        Task {
            try? await Task.sleep(for: .seconds(2))
            copyStatus = nil
        }
    }
}

private struct MCPSettingsConnection: Identifiable {
    let workspace: String
    let connection: DatabaseConnection

    var id: UUID {
        connection.id
    }

    var toolNames: [String] {
        [
            MCPToolService.listTablesToolName(for: connection),
            MCPToolService.describeTableToolName(for: connection),
            MCPToolService.previewTableToolName(for: connection),
            MCPToolService.queryToolName(for: connection)
        ]
    }
}

private struct StorageLocationView: View {
    private var fileURL: URL? {
        AppStatePersistence.defaultFileURL
    }

    var body: some View {
        SettingsCard(title: "Storage") {
            VStack(alignment: .leading, spacing: 7) {
                Text("Workspace state")
                Text(fileURL?.path(percentEncoded: false) ?? "Unavailable")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Label("Passwords stay in macOS Keychain.", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") {
                    guard let fileURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .disabled(fileURL == nil)
            }
        }
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        guard let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Development build"
        }
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              build != shortVersion else {
            return "Version \(shortVersion)"
        }
        return "Version \(shortVersion) (\(build))"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright 2026 Pluto Labs. All rights reserved."
    }

    var body: some View {
        SettingsPage(title: "About", subtitle: "Native database workbench for macOS.") {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 86, height: 86)
                    .accessibilityHidden(true)
                Text("Selektos")
                    .font(.title.bold())
                Text(version)
                    .foregroundStyle(.secondary)
                Text("Published by Pluto Labs")
                    .font(.headline)
                Text("PostgreSQL and Cloudflare D1 query editor built with SwiftUI, AppKit, and Swift concurrency.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 430)
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator.opacity(0.55))
            }
        }
    }
}

private struct SettingsHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
