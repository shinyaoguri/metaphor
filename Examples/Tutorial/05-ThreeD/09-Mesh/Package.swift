// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Mesh3D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Mesh3D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Mesh3D"
        ),
    ]
)
