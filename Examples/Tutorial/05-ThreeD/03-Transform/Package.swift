// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Transform3D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Transform3D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Transform3D"
        ),
    ]
)
