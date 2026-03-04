// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DepthSort",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DepthSort",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DepthSort"
        ),
    ]
)
