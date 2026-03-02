// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MPSShowcase",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MPSShowcase",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "MPSShowcase"
        ),
    ]
)
