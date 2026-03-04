// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Noise1D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Noise1D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Noise1D"
        ),
    ]
)
