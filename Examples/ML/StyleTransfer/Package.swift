// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StyleTransfer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "StyleTransfer",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "StyleTransfer"
        ),
    ]
)
