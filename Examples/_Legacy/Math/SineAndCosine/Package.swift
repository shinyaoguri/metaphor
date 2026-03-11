// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SineAndCosine",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SineAndCosine",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "SineAndCosine"
        ),
    ]
)
