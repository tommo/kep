// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kep",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KepModel", targets: ["KepModel"]),
        .library(name: "KepCore", targets: ["KepCore"]),
        .library(name: "KepBase", targets: ["KepBase"]),
        .library(name: "KepMindMap", targets: ["KepMindMap"]),
        .library(name: "KepMarkdown", targets: ["KepMarkdown"]),
        .library(name: "KepPlantUML", targets: ["KepPlantUML"]),
        .library(name: "KepCSV", targets: ["KepCSV"]),
        .library(name: "KepGenAI", targets: ["KepGenAI"]),
        .library(name: "KepScript", targets: ["KepScript"]),
        .library(name: "KepBridge", targets: ["KepBridge"]),
        .executable(name: "KepApp", targets: ["KepApp"]),
        .executable(name: "kep", targets: ["kep"]),
        .executable(name: "kep-mcp", targets: ["kep-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        .package(url: "https://github.com/ChrisGVE/LuaSwift.git", from: "1.12.0"),
    ],
    targets: [
        .target(
            name: "KepModel",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "KepCore",
            dependencies: [
                "KepModel",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "KepBase",
            dependencies: [
                "KepCore", "KepModel",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(name: "KepMindMap", dependencies: ["KepBase", "KepCore", "KepModel", "KepMarkdown"]),
        .target(
            name: "KepMarkdown",
            dependencies: [
                "KepBase",
                "KepCore",
                .product(name: "Markdown", package: "swift-markdown"),
                "SwiftSoup",
            ]
        ),
        .target(name: "KepPlantUML", dependencies: ["KepBase", "KepCore"]),
        .target(name: "KepCSV", dependencies: [
            "KepBase", "KepScript",
            .product(name: "LuaSwift", package: "LuaSwift"),
        ]),
        .target(name: "KepGenAI", dependencies: ["KepBase", "KepCore", "KepMarkdown"]),
        // Lua-backed scripting: embeds LuaSwift (vendored Lua, no system dep) and
        // exposes a `kep` API to scripts. NOT a custom language.
        .target(
            name: "KepScript",
            dependencies: [
                "KepCore", "KepModel",
                .product(name: "LuaSwift", package: "LuaSwift"),
            ]
        ),
        .executableTarget(
            name: "KepApp",
            dependencies: [
                "KepModel", "KepCore", "KepBase",
                "KepMindMap", "KepMarkdown", "KepPlantUML",
                "KepCSV", "KepGenAI", "KepScript", "KepBridge",
            ],
            resources: [.process("Resources")]
        ),

        // Local IPC bridge: a tiny JSON line-protocol + Unix-socket client/server
        // so external agents (CLI, MCP) drive the RUNNING kep app. No Kep deps
        // — the clients stay decoupled; the app links it to run the server.
        .target(name: "KepBridge"),
        .executableTarget(name: "kep", dependencies: ["KepBridge"]),
        .executableTarget(name: "kep-mcp", dependencies: ["KepBridge"]),

        .testTarget(name: "KepBridgeTests", dependencies: ["KepBridge"]),
        .testTarget(
            name: "KepModelTests",
            dependencies: ["KepModel"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "KepCoreTests", dependencies: ["KepCore", "KepBase"]),
        .testTarget(name: "KepMindMapTests", dependencies: ["KepMindMap", "KepMarkdown", "KepBase", "KepPlantUML", "KepCSV", "KepGenAI"]),
        .testTarget(name: "KepScriptTests", dependencies: ["KepScript", "KepModel"]),
    ]
)
