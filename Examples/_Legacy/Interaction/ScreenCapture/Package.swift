// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenCapture",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ScreenCapture",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "ScreenCapture"
        ),
    ]
)
