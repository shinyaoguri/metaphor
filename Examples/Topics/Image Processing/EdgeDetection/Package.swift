// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "EdgeDetection",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "EdgeDetection",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "EdgeDetection"
        ),
    ]
)
