// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResizeTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ResizeTest",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ResizeTest"
        ),
    ]
)
