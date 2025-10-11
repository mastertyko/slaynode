// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SlayNodeMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SlayNodeMenuBar",
            targets: ["SlayNodeMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SlayNodeMenuBar",
            path: "Sources",
            resources: [
                .process("SlayNodeMenuBar/Resources")
            ]
        ),
        .testTarget(
            name: "SlayNodeMenuBarTests",
            dependencies: ["SlayNodeMenuBar"],
            path: "Tests/SlayNodeMenuBarTests"
        )
    ]
)
