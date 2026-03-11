// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TileImages",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TileImages",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TileImages"
        ),
    ]
)
