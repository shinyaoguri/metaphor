// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextRendering",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TextRendering",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TextRendering"
        ),
    ]
)
