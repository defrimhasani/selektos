import AppKit
import Darwin
import SwiftUI

@main
enum SelektosLauncher {
    @MainActor
    static func main() async {
        if CommandLine.arguments.dropFirst().contains("--mcp-server") {
            do {
                try await MCPServerCommand.run()
            } catch {
                let message = "Selektos MCP server failed: \(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(message.utf8))
                Darwin.exit(EXIT_FAILURE)
            }
        } else {
            SelektosApp.main()
        }
    }
}

struct SelektosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @AppStorage(AppPreferences.appearanceKey) private var appearance = AppAppearance.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        AppAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: store)
                .frame(minWidth: 1_080, minHeight: 680)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 1_420, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Query") { store.addQuery() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(store: store)
                .preferredColorScheme(preferredColorScheme)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
