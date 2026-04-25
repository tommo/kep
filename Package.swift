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
        .executable(name: "Mindo", targets: ["Mindo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
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
        .target(name: "MindoMindMap", dependencies: ["MindoBase", "MindoModel"]),
        .target(
            name: "MindoMarkdown",
            dependencies: [
                "MindoBase",
                .product(name: "Markdown", package: "swift-markdown"),
                "SwiftSoup",
            ]
        ),
        .target(name: "MindoPlantUML", dependencies: ["MindoBase"]),
        .target(name: "MindoCSV", dependencies: ["MindoBase"]),
        .target(name: "MindoGenAI", dependencies: ["MindoBase"]),
        .executableTarget(
            name: "Mindo",
            dependencies: [
                "MindoModel", "MindoCore", "MindoBase",
                "MindoMindMap", "MindoMarkdown", "MindoPlantUML",
                "MindoCSV", "MindoGenAI",
            ],
            resources: [.process("Resources")]
        ),

        .testTarget(
            name: "MindoModelTests",
            dependencies: ["MindoModel"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MindoCoreTests", dependencies: ["MindoCore", "MindoBase"]),
        .testTarget(name: "MindoMindMapTests", dependencies: ["MindoMindMap", "MindoMarkdown", "MindoPlantUML", "MindoCSV", "MindoGenAI"]),
    ]
)
