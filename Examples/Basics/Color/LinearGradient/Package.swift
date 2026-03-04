// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LinearGradient",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LinearGradient",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LinearGradient"
        ),
    ]
)
