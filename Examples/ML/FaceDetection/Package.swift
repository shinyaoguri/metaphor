// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FaceDetection",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "FaceDetection",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "FaceDetection"
        ),
    ]
)
