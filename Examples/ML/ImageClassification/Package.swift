// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImageClassification",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ImageClassification",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "ImageClassification"
        ),
    ]
)
