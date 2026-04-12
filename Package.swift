// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParsoIRCTests",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "IRCTests",
            dependencies: [],
            path: "Tests"
        ),
    ]
)