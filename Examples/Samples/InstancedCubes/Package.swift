// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "InstancedCubes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "InstancedCubes",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "InstancedCubes"
        ),
    ]
)
