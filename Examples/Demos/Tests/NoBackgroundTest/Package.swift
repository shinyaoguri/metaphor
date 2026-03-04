// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoBackgroundTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "NoBackgroundTest",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "NoBackgroundTest"
        ),
    ]
)
