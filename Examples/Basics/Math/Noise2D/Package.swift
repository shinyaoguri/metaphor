// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Noise2D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Noise2D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Noise2D"
        ),
    ]
)
