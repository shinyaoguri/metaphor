// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DynamicParticlesImmediate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DynamicParticlesImmediate",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DynamicParticlesImmediate"
        ),
    ]
)
