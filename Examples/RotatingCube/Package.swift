// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RotatingCube",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "RotatingCube",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "RotatingCube"
        ),
    ]
)
