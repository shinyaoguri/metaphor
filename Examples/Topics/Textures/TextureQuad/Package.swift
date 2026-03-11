// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "TextureQuad",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TextureQuad",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TextureQuad"
        ),
    ]
)
