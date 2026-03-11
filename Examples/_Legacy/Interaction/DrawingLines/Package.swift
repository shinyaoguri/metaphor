// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DrawingLines",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DrawingLines",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "DrawingLines"
        ),
    ]
)
