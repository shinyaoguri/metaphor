// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LoadSaveJSON",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LoadSaveJSON",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LoadSaveJSON"
        ),
    ]
)
