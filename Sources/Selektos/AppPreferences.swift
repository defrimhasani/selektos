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
}
