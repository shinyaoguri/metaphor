// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Distance2D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Distance2D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Distance2D"
        ),
    ]
)
