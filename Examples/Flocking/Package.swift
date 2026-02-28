// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Flocking",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Flocking",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "Flocking"
        ),
    ]
)
