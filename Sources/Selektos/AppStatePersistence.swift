import Foundation

struct AppStatePersistence: Sendable {
    let fileURL: URL?

    init(fileURL: URL? = AppStatePersistence.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Selektos", directoryHint: .isDirectory)
    }

    static var defaultFileURL: URL? {
        defaultDirectoryURL?.appending(path: "workspaces.json")
    }

    func load() -> AppState? {
        try? loadValidated()
    }

    func loadValidated() throws -> AppState? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(AppState.self, from: Data(contentsOf: fileURL))
    }

    func save(_ state: AppState) throws {
        guard let fileURL else {
            throw AppStatePersistenceError.applicationSupportUnavailable
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }
}

private enum AppStatePersistenceError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        "The Application Support directory is unavailable."
    }
}
