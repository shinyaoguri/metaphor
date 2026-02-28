// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RecursiveTree",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "RecursiveTree",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "RecursiveTree"
        ),
    ]
)
