// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColorDemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ColorDemo",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "ColorDemo"
        ),
    ]
)
