// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SaveFrames",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SaveFrames",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SaveFrames"
        ),
    ]
)
