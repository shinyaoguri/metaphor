// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NoiseBasics",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "NoiseBasics",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "NoiseBasics"
        ),
    ]
)
