// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BlendModes",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BlendModes",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "BlendModes"
        ),
    ]
)
