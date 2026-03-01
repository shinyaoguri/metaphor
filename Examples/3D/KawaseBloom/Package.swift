// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KawaseBloom",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "KawaseBloom",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "KawaseBloom"
        ),
    ]
)
