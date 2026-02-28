// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sketch2D",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Sketch2D",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "Sketch2D"
        ),
    ]
)
