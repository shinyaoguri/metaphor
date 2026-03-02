// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NextGenShowcase",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "NextGenShowcase",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "NextGenShowcase"
        ),
    ]
)
