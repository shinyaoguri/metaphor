// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MLVision2Showcase",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MLVision2Showcase",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "MLVision2Showcase"
        ),
    ]
)
