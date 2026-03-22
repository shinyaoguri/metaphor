// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SceneGraphBasics",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SceneGraphBasics",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SceneGraphBasics"
        ),
    ]
)
