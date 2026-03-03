// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersonSegmentation",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PersonSegmentation",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "PersonSegmentation"
        ),
    ]
)
