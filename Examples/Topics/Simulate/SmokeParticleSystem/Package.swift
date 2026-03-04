// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SmokeParticleSystem",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SmokeParticleSystem",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SmokeParticleSystem"
        ),
    ]
)
