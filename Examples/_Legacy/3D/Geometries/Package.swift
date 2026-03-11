// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Geometries",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Geometries",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "Geometries"
        ),
    ]
)
