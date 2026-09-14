import XCTest
@testable import Selektos

@MainActor
final class AppStoreSettingsTests: XCTestCase {
    func testWorkspaceManagement() {
        let first = Workspace(name: "First")
        let second = Workspace(name: "Second")
        let store = AppStore(
            initialState: AppState(workspaces: [first, second], selectedWorkspaceID: first.id),
            persistsState: false
        )

        store.renameWorkspace(second.id, to: "Renamed")
        XCTAssertEqual(store.state.workspaces[1].name, "Renamed")

        store.selectWorkspace(second.id)
        XCTAssertEqual(store.selectedWorkspace?.id, second.id)

        store.deleteWorkspace(second.id)
        XCTAssertEqual(store.state.workspaces.map(\.id), [first.id])
        XCTAssertEqual(store.selectedWorkspace?.id, first.id)
    }

    func testLastWorkspaceCannotBeDeleted() {
        let only = Workspace(name: "Only")
        let store = AppStore(
            initialState: AppState(workspaces: [only], selectedWorkspaceID: only.id),
            persistsState: false
        )

        store.deleteWorkspace(only.id)

        XCTAssertEqual(store.state.workspaces.map(\.id), [only.id])
        XCTAssertEqual(store.selectedWorkspace?.id, only.id)
    }

    func testNewWorkspaceUsesConfiguredDefaultQuery() {
        let key = AppPreferences.defaultQueryKey
        let oldValue = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set("SELECT 42;", forKey: key)
        defer {
            if let oldValue {
                UserDefaults.standard.set(oldValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let first = Workspace(name: "First")
        let store = AppStore(
            initialState: AppState(workspaces: [first], selectedWorkspaceID: first.id),
            persistsState: false
        )

        store.addWorkspace(named: "New")

        XCTAssertEqual(store.selectedWorkspace?.name, "New")
        XCTAssertEqual(store.selectedWorkspace?.queryTabs.first?.sql, "SELECT 42;")
    }

    func testD1ConnectionUsesCompatibleDefaultQuery() {
        let connection = d1Connection()
        var workspace = Workspace(name: "D1")
        workspace.connections = [connection]
        workspace.queryTabs[0].connectionID = connection.id
        workspace.queryTabs[0].sql = AppPreferences.defaultQuery

        let store = AppStore(
            initialState: AppState(
                workspaces: [workspace],
                selectedWorkspaceID: workspace.id
            ),
            persistsState: false
        )

        XCTAssertEqual(store.selectedQuery?.sql, "SELECT 1 AS result;")

        store.addQuery()

        XCTAssertEqual(store.selectedQuery?.sql, "SELECT 1 AS result;")
        XCTAssertEqual(store.selectedQuery?.connectionID, connection.id)
    }

    func testSelectingD1ConnectionDoesNotReplaceEditedQuery() {
        let connection = d1Connection()
        var workspace = Workspace(name: "D1")
        workspace.connections = [connection]
        workspace.queryTabs[0].sql = "SELECT 42;"
        let store = AppStore(
            initialState: AppState(
                workspaces: [workspace],
                selectedWorkspaceID: workspace.id
            ),
            persistsState: false
        )

        store.selectConnection(connection.id)

        XCTAssertEqual(store.selectedQuery?.sql, "SELECT 42;")
    }

    func testOpeningTableRunsLimitedQueryInCurrentTab() {
        let connection = d1Connection()
        var workspace = Workspace(name: "D1")
        workspace.connections = [connection]
        workspace.queryTabs[0].connectionID = connection.id
        workspace.queryTabs[0].sql = "SELECT 42;"
        let store = AppStore(
            initialState: AppState(
                workspaces: [workspace],
                selectedWorkspaceID: workspace.id
            ),
            persistsState: false
        )
        let table = DatabaseTable(
            schema: "main",
            name: "order\"details",
            columns: []
        )

        store.queryTable(table, connectionID: connection.id)

        XCTAssertEqual(store.selectedWorkspace?.queryTabs.count, 1)
        XCTAssertEqual(
            store.selectedQuery?.sql,
            "SELECT *\nFROM \"main\".\"order\"\"details\"\nLIMIT 100;"
        )
        XCTAssertEqual(store.selectedQuery?.schema, "main")
        XCTAssertTrue(store.isExecuting)
        store.cancelQuery()
    }

    func testResultRowSelectionIsValidatedAndClearedWithExecutionContext() {
        var workspace = Workspace(name: "Rows")
        let secondQuery = QueryTab(title: "Second", sql: "SELECT 2;")
        workspace.queryTabs.append(secondQuery)
        let store = AppStore(
            initialState: AppState(
                workspaces: [workspace],
                selectedWorkspaceID: workspace.id
            ),
            persistsState: false
        )
        store.result = QueryResult(
            columns: ["id", "name"],
            rows: [
                QueryResultRow(id: 0, values: ["1", "Ada"]),
                QueryResultRow(id: 1, values: ["2", "Grace"])
            ],
            command: "SELECT",
            duration: .milliseconds(4)
        )

        store.selectResultRow(1)
        XCTAssertEqual(store.selectedResultRow?.values, ["2", "Grace"])

        store.selectResultRow(99)
        XCTAssertNil(store.selectedResultRow)

        store.selectResultRow(0)
        store.selectQuery(secondQuery.id)
        XCTAssertNil(store.result)
        XCTAssertNil(store.selectedResultRowID)
    }

    private func d1Connection() -> DatabaseConnection {
        DatabaseConnection(
            kind: .cloudflareD1,
            name: "Cloudflare D1",
            host: "",
            port: 0,
            database: "example",
            username: "",
            tlsMode: .prefer,
            labels: [],
            d1Database: "example",
            wranglerPath: "wrangler",
            wranglerProfile: ""
        )
    }
}
