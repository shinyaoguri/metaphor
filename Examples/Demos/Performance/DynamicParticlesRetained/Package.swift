// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DynamicParticlesRetained",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DynamicParticlesRetained",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DynamicParticlesRetained"
        ),
    ]
)
