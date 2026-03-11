// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "GameOfLife",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "GameOfLife",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "GameOfLife"
        ),
    ]
)
