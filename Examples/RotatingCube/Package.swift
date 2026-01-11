// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RotatingCube",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "RotatingCube",
            dependencies: ["metaphor"],
            path: "RotatingCube"
        ),
    ]
)
