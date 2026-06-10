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
        // No `.unsafeFlags` anywhere: SwiftPM refuses to resolve packages that
        // use them as remote dependencies, and -Ounchecked/-ffast-math trade
        // memory safety for negligible gains in a parser of untrusted input.
        // Release builds already get optimized code from SwiftPM defaults.
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
