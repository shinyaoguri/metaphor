// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TextDemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TextDemo",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "TextDemo"
        ),
    ]
)
