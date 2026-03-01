// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioReactive",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "AudioReactive",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "AudioReactive"
        ),
    ]
)
