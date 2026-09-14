// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Selektos",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Selektos", targets: ["Selektos"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .executableTarget(
            name: "Selektos",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/Selektos"
        ),
        .testTarget(
            name: "SelektosTests",
            dependencies: ["Selektos"],
            path: "Tests/SelektosTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
