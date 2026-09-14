#!/usr/bin/swift

import AppKit
import Foundation

enum IconGeneratorError: LocalizedError {
    case cannotLoadSource(URL)
    case cannotCreateBitmap(Int)
    case cannotEncodePNG(Int)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case let .cannotLoadSource(url):
            "Could not load icon source at \(url.path)."
        case let .cannotCreateBitmap(size):
            "Could not create the \(size)x\(size) icon bitmap."
        case let .cannotEncodePNG(size):
            "Could not encode the \(size)x\(size) icon as PNG."
        case let .commandFailed(command, status):
            "\(command) exited with status \(status)."
        }
    }
}

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = repositoryRoot.appending(path: "Assets/SelektosIcon.svg")
let pngURL = repositoryRoot.appending(path: "Assets/SelektosIcon.png")
let icnsURL = repositoryRoot.appending(path: "Distribution/Selektos.icns")

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw IconGeneratorError.cannotLoadSource(sourceURL)
}

func pngData(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconGeneratorError.cannotCreateBitmap(size)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGeneratorError.cannotCreateBitmap(size)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGeneratorError.cannotEncodePNG(size)
    }
    return data
}

func run(_ executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw IconGeneratorError.commandFailed(
            ([executable] + arguments).joined(separator: " "),
            process.terminationStatus
        )
    }
}

try fileManager.createDirectory(
    at: pngURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try fileManager.createDirectory(
    at: icnsURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData(size: 1024).write(to: pngURL, options: .atomic)

let temporaryDirectory = fileManager.temporaryDirectory
    .appending(path: "Selektos-\(UUID().uuidString)", directoryHint: .isDirectory)
let iconsetURL = temporaryDirectory.appending(path: "Selektos.iconset", directoryHint: .isDirectory)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryDirectory) }

let representations: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for representation in representations {
    let outputURL = iconsetURL.appending(path: representation.name)
    try pngData(size: representation.size).write(to: outputURL, options: .atomic)
}

if fileManager.fileExists(atPath: icnsURL.path) {
    try fileManager.removeItem(at: icnsURL)
}
try run(
    "/usr/bin/iconutil",
    arguments: ["--convert", "icns", "--output", icnsURL.path, iconsetURL.path]
)

print("Generated \(pngURL.path)")
print("Generated \(icnsURL.path)")
