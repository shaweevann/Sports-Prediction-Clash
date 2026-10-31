// swift-tools-version: 6.0
import PackageDescription

// The game server. It compiles the app's own engine files, so prices, drives and settlement
// are the same code on the phone and on the server.
let engine = "SportsPredictionClash/SportsPredictionClash/Engine"

let package = Package(
    name: "ClashServer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClashServer",
            path: ".",
            // Everything in the repo that isn't server code
            exclude: [
                "sports-prediction-clash.html",
                "sports-prediction-clash-logo.png",
                "server-data",
                "Server/Tests",
                "SportsPredictionClash/Tools",
                "SportsPredictionClash/SportsPredictionClash/Assets.xcassets",
                "SportsPredictionClash/SportsPredictionClash/Views",
                "SportsPredictionClash/SportsPredictionClash/SportsPredictionClashApp.swift",
                "\(engine)/GameModel.swift",
                "\(engine)/Social.swift",
                "\(engine)/ClashAPI.swift",
            ],
            sources: [
                "\(engine)/DriveEngine.swift",
                "\(engine)/Markets.swift",
                "\(engine)/Pricing.swift",
                "\(engine)/Game.swift",
                "\(engine)/API.swift",
                "Server/Sources",
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClashServerTests",
            dependencies: ["ClashServer"],
            path: "Server/Tests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
