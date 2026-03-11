// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OSCDemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "OSCDemo",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "OSCDemo"
        ),
    ]
)
