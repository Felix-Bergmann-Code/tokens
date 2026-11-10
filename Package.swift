// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tokens",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Tokens",
            path: "Sources/Tokens",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
