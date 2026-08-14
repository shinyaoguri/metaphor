// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Text2D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Text2D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Text2D"
        ),
    ]
)
