// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "RenderGraphCompose",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RenderGraphCompose",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RenderGraphCompose"
        ),
    ]
)
