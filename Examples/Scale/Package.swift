// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Scale",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../.."),
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
