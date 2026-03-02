// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FillStroke3D",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "FillStroke3D",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "FillStroke3D"
        ),
    ]
)
