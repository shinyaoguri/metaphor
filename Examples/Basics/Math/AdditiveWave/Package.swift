// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AdditiveWave",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "AdditiveWave",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "AdditiveWave"
        ),
    ]
)
