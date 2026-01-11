// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Particles",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Particles",
            dependencies: ["metaphor"],
            path: "Particles"
        ),
    ]
)
