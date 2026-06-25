// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mindo",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MindoModel", targets: ["MindoModel"]),
        .library(name: "MindoCore", targets: ["MindoCore"]),
        .library(name: "MindoBase", targets: ["MindoBase"]),
        .library(name: "MindoMindMap", targets: ["MindoMindMap"]),
        .library(name: "MindoMarkdown", targets: ["MindoMarkdown"]),
        .library(name: "MindoPlantUML", targets: ["MindoPlantUML"]),
        .library(name: "MindoCSV", targets: ["MindoCSV"]),
        .library(name: "MindoGenAI", targets: ["MindoGenAI"]),
        .library(name: "MindoScript", targets: ["MindoScript"]),
        .library(name: "KepBridge", targets: ["KepBridge"]),
        .executable(name: "Mindo", targets: ["Mindo"]),
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
            name: "MindoModel",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "MindoCore",
            dependencies: [
                "MindoModel",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "MindoBase",
            dependencies: [
                "MindoCore", "MindoModel",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(name: "MindoMindMap", dependencies: ["MindoBase", "MindoCore", "MindoModel", "MindoMarkdown"]),
        .target(
            name: "MindoMarkdown",
            dependencies: [
                "MindoBase",
                "MindoCore",
                .product(name: "Markdown", package: "swift-markdown"),
                "SwiftSoup",
            ]
        ),
        .target(name: "MindoPlantUML", dependencies: ["MindoBase", "MindoCore"]),
        .target(name: "MindoCSV", dependencies: [
            "MindoBase", "MindoScript",
            .product(name: "LuaSwift", package: "LuaSwift"),
        ]),
        .target(name: "MindoGenAI", dependencies: ["MindoBase", "MindoCore", "MindoMarkdown"]),
        // Lua-backed scripting: embeds LuaSwift (vendored Lua, no system dep) and
        // exposes a `mindo` API to scripts. NOT a custom language.
        .target(
            name: "MindoScript",
            dependencies: [
                "MindoCore", "MindoModel",
                .product(name: "LuaSwift", package: "LuaSwift"),
            ]
        ),
        .executableTarget(
            name: "Mindo",
            dependencies: [
                "MindoModel", "MindoCore", "MindoBase",
                "MindoMindMap", "MindoMarkdown", "MindoPlantUML",
                "MindoCSV", "MindoGenAI", "MindoScript", "KepBridge",
            ],
            resources: [.process("Resources")]
        ),

        // Local IPC bridge: a tiny JSON line-protocol + Unix-socket client/server
        // so external agents (CLI, MCP) drive the RUNNING kep app. No Mindo deps
        // — the clients stay decoupled; the app links it to run the server.
        .target(name: "KepBridge"),
        .executableTarget(name: "kep", dependencies: ["KepBridge"]),
        .executableTarget(name: "kep-mcp", dependencies: ["KepBridge"]),

        .testTarget(name: "KepBridgeTests", dependencies: ["KepBridge"]),
        .testTarget(
            name: "MindoModelTests",
            dependencies: ["MindoModel"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MindoCoreTests", dependencies: ["MindoCore", "MindoBase"]),
        .testTarget(name: "MindoMindMapTests", dependencies: ["MindoMindMap", "MindoMarkdown", "MindoBase", "MindoPlantUML", "MindoCSV", "MindoGenAI"]),
        .testTarget(name: "MindoScriptTests", dependencies: ["MindoScript", "MindoModel"]),
    ]
)
