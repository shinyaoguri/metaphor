// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MLShowcase",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MLShowcase",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "MLShowcase"
        ),
    ]
)
