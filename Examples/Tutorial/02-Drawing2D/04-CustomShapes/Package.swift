// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "CustomShapes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CustomShapes",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CustomShapes"
        ),
    ]
)
