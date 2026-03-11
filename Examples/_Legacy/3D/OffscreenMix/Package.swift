// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OffscreenMix",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "OffscreenMix",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "OffscreenMix"
        ),
    ]
)
