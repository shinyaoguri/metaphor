// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ParticleSystemPShape",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ParticleSystemPShape",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ParticleSystemPShape"
        ),
    ]
)
