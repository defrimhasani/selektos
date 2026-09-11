import XCTest
@testable import Selektos

final class WranglerExecutableResolverTests: XCTestCase {
    func testFindsWranglerInNewestNVMNodeInstallation() throws {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let olderWrangler = homeDirectory
            .appendingPathComponent(".nvm/versions/node/v20.18.0/bin/wrangler")
        let newerWrangler = homeDirectory
            .appendingPathComponent(".nvm/versions/node/v24.14.1/bin/wrangler")
        try createExecutable(at: olderWrangler)
        try createExecutable(at: newerWrangler)

        let resolver = WranglerExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: homeDirectory,
            standardSearchDirectories: []
        )

        XCTAssertEqual(try resolver.resolve("wrangler"), newerWrangler)
    }

    func testProcessEnvironmentPrependsWranglerBinDirectory() {
        let executable = URL(fileURLWithPath: "/Users/example/.nvm/versions/node/v24/bin/wrangler")
        let resolver = WranglerExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            standardSearchDirectories: []
        )

        let environment = resolver.processEnvironment(for: executable)
        let pathDirectories = environment["PATH"]?.split(separator: ":").map(String.init)

        XCTAssertEqual(pathDirectories?.first, executable.deletingLastPathComponent().path)
        XCTAssertEqual(environment["NO_COLOR"], "1")
    }

    func testFormatsCloudflareErrorWithDiagnosticNotes() throws {
        let data = try XCTUnwrap(
            """
            {
              "error": {
                "text": "A request to the Cloudflare API failed.",
                "notes": [
                  { "text": "no such function: version: SQLITE_ERROR [code: 7500]" }
                ]
              }
            }
            """.data(using: .utf8)
        )

        XCTAssertEqual(
            WranglerErrorFormatter.message(from: data),
            """
            A request to the Cloudflare API failed.
            no such function: version: SQLITE_ERROR [code: 7500]
            """
        )
    }

    private func createExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: url.path,
                contents: Data("#!/usr/bin/env node\n".utf8)
            )
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
