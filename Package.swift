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
            name: "IRCStandaloneTests",
            dependencies: [],
            path: ".",
            sources: ["Tests/LinuxStandaloneTests.swift"]
        ),
    ]
)