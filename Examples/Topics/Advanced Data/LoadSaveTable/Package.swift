// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LoadSaveTable",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LoadSaveTable",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LoadSaveTable"
        ),
    ]
)
