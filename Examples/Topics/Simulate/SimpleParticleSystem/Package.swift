// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SimpleParticleSystem",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SimpleParticleSystem",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SimpleParticleSystem"
        ),
    ]
)
