// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VideoRecord",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "VideoRecord",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "VideoRecord"
        ),
    ]
)
