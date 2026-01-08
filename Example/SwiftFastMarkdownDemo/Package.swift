// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftFastMarkdownDemo",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "SwiftFastMarkdownDemo",
            targets: ["SwiftFastMarkdownDemo"]
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SwiftFastMarkdownDemo",
            dependencies: [
                .product(name: "SwiftFastMarkdown", package: "swift-fast-markdown")
            ],
            path: "."
        )
    ]
)
