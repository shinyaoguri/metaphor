// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NoiseField",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "NoiseField",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "NoiseField"
        ),
    ]
)
