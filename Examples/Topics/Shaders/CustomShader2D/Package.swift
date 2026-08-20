// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "CustomShader2D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CustomShader2D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CustomShader2D",
            resources: [.copy("Resources")]
        ),
    ]
)
