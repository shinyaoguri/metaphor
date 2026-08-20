// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ShapeShader",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ShapeShader",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ShapeShader"
        ),
    ]
)
