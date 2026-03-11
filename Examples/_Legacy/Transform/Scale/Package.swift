// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Scale",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Scale",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "Scale"
        ),
    ]
)
