// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Star",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Star",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Star"
        ),
    ]
)
