// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sketch3D",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Sketch3D",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "Sketch3D"
        ),
    ]
)
