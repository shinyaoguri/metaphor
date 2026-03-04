// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Primitives3D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Primitives3D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Primitives3D"
        ),
    ]
)
