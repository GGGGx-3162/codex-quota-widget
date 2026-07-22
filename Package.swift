// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CodexGauge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexGauge", targets: ["CodexGauge"])
    ],
    targets: [
        .executableTarget(
            name: "CodexGauge",
            path: "Sources/CodexGauge"
        )
    ]
)
