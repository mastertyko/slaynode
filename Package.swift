// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SlayNodeMenuBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "SlayNodeMenuBar",
            targets: ["SlayNodeMenuBar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0")
    ],
    targets: [
        .executableTarget(
            name: "SlayNodeMenuBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
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
