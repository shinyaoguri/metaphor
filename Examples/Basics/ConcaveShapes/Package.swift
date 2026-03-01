// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ConcaveShapes",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ConcaveShapes",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "ConcaveShapes"
        ),
    ]
)
