import Foundation

struct MCPSettings: Equatable, Sendable {
    let isEnabled: Bool
    let isReadOnly: Bool
    let maximumRows: Int

    static func sessionSettings(
        startup: MCPSettings,
        current: MCPSettings
    ) -> MCPSettings {
        MCPSettings(
            isEnabled: current.isEnabled,
            isReadOnly: startup.isReadOnly,
            maximumRows: startup.maximumRows
        )
    }
}

enum MCPPreferences {
    static let suiteName = "com.plutolabs.selektos.mcp"
    static let enabledKey = "mcp.enabled"
    static let readOnlyKey = "mcp.readOnly"
    static let maximumRowsKey = "mcp.maximumRows"
    static let rowLimitOptions = [100, 500, 1_000, 5_000, 10_000]
    static let defaultMaximumRows = 1_000

    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create the Selektos preferences store.")
        }
        return defaults
    }()

    static func registerDefaults() {
        defaults.register(defaults: [
            enabledKey: false,
            readOnlyKey: true,
            maximumRowsKey: defaultMaximumRows
        ])
    }

    static var current: MCPSettings {
        registerDefaults()
        _ = defaults.synchronize()
        let configuredMaximum = defaults.integer(forKey: maximumRowsKey)
        return MCPSettings(
            isEnabled: defaults.bool(forKey: enabledKey),
            isReadOnly: defaults.bool(forKey: readOnlyKey),
            maximumRows: rowLimitOptions.contains(configuredMaximum)
                ? configuredMaximum
                : defaultMaximumRows
        )
    }

    static func clientConfigurationJSON(executableURL: URL? = Bundle.main.executableURL) -> String {
        let executablePath = executableURL?.path
            ?? "/Applications/Selektos.app/Contents/MacOS/Selektos"
        let configuration: [String: Any] = [
            "mcpServers": [
                "selektos": [
                    "command": executablePath,
                    "args": ["--mcp-server"]
                ]
            ]
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: configuration,
                options: [.prettyPrinted, .sortedKeys]
            )
            return String(decoding: data, as: UTF8.self)
        } catch {
            preconditionFailure("Could not encode the MCP client configuration: \(error)")
        }
    }
}
