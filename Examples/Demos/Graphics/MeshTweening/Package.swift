// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MeshTweening",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MeshTweening",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MeshTweening"
        ),
    ]
)
