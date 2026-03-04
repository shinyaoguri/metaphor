// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "StaticParticlesRetained",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "StaticParticlesRetained",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "StaticParticlesRetained"
        ),
    ]
)
