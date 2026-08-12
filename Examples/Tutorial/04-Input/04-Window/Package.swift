// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Window",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Window",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Window"
        ),
    ]
)
