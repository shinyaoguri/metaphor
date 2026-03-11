// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LineRendering",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LineRendering",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LineRendering"
        ),
    ]
)
