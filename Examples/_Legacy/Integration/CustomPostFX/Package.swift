// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CustomPostFX",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CustomPostFX",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "CustomPostFX"
        ),
    ]
)
