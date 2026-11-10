// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CWNotebook",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "CWNotebook",
            path: "Sources/CWNotebook",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
