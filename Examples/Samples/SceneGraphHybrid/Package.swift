// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SceneGraphHybrid",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SceneGraphHybrid",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SceneGraphHybrid"
        ),
    ]
)
