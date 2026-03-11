// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ColorWheel",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ColorWheel",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "ColorWheel"
        ),
    ]
)
