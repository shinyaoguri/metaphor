// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "EmbeddedIteration",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "EmbeddedIteration",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "EmbeddedIteration"
        ),
    ]
)
