// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FeatureShowcase",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "FeatureShowcase",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "FeatureShowcase",
            resources: [
                .copy("Resources/diamond.obj")
            ]
        ),
    ]
)
