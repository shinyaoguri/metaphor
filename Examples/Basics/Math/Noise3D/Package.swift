// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Noise3D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Noise3D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Noise3D"
        ),
    ]
)
