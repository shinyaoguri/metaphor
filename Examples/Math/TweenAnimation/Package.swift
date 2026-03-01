// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TweenAnimation",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TweenAnimation",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "TweenAnimation"
        ),
    ]
)
