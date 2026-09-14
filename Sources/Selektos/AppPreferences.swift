import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppPreferences {
    static let appearanceKey = "settings.appearance"
    static let editorFontSizeKey = "settings.editorFontSize"
    static let showLineNumbersKey = "settings.showLineNumbers"
    static let showInspectorKey = "settings.showInspector"
    static let restoreLastWorkspaceKey = "settings.restoreLastWorkspace"
    static let automaticallyLoadMetadataKey = "settings.automaticallyLoadMetadata"
    static let resultRowLimitKey = "settings.resultRowLimit"
    static let defaultQueryKey = "settings.defaultQuery"
    static let selectedSettingsPaneKey = "settings.selectedPane"

    static let defaultQuery = "SELECT version();"
    static let d1DefaultQuery = "SELECT 1 AS result;"
    static let rowLimitOptions = [1_000, 5_000, 10_000, 25_000]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            appearanceKey: AppAppearance.system.rawValue,
            editorFontSizeKey: 14.0,
            showLineNumbersKey: true,
            showInspectorKey: true,
            restoreLastWorkspaceKey: true,
            automaticallyLoadMetadataKey: true,
            resultRowLimitKey: 10_000,
            defaultQueryKey: defaultQuery,
            selectedSettingsPaneKey: "general"
        ])
        MCPPreferences.registerDefaults()
    }

    static var resultRowLimit: Int {
        let value = UserDefaults.standard.integer(forKey: resultRowLimitKey)
        return rowLimitOptions.contains(value) ? value : 10_000
    }

    static var defaultQueryText: String {
        guard let value = UserDefaults.standard.string(forKey: defaultQueryKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return defaultQuery }
        return value
    }

    static func defaultQueryText(for connectionKind: ConnectionKind?) -> String {
        let configuredQuery = defaultQueryText
        guard connectionKind == .cloudflareD1, configuredQuery == defaultQuery else {
            return configuredQuery
        }
        return d1DefaultQuery
    }

    static func isBuiltInDefaultQuery(_ sql: String) -> Bool {
        let query = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        return query == defaultQuery || query == d1DefaultQuery
    }
}
