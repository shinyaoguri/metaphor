// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "EdgeDetect",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "EdgeDetect",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "EdgeDetect"
        ),
    ]
)
