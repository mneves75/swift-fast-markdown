// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftFastMarkdown",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftFastMarkdown",
            targets: ["SwiftFastMarkdown"]
        ),
        .executable(
            name: "SwiftFastMarkdownBenchmarks",
            targets: ["SwiftFastMarkdownBenchmarks"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0")
    ],
    targets: [
        .target(
            name: "CMD4C",
            path: "Sources/CMD4C",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SwiftFastMarkdown",
            dependencies: [
                "CMD4C",
                .product(name: "Highlightr", package: "Highlightr")
            ],
            path: "Sources/SwiftFastMarkdown",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"]),
                .unsafeFlags(["-disable-actor-data-race-checks"])
            ]
        ),
        .executableTarget(
            name: "SwiftFastMarkdownBenchmarks",
            dependencies: ["SwiftFastMarkdown"],
            path: "Benchmarks"
        ),
        .testTarget(
            name: "SwiftFastMarkdownTests",
            dependencies: ["SwiftFastMarkdown"],
            path: "Tests/SwiftFastMarkdownTests"
        )
    ]
)
