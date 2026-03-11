// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Graphing2DEquation",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Graphing2DEquation",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Graphing2DEquation"
        ),
    ]
)
