// swift-tools-version: 5.10
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
