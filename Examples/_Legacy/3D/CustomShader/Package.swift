// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CustomShader",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CustomShader",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "CustomShader"
        ),
    ]
)
