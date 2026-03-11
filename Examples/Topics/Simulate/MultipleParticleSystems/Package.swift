// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MultipleParticleSystems",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MultipleParticleSystems",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MultipleParticleSystems"
        ),
    ]
)
