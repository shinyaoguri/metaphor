// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NoiseWave",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "NoiseWave",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "NoiseWave"
        ),
    ]
)
