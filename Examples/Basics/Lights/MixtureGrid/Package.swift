// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MixtureGrid",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MixtureGrid",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MixtureGrid"
        ),
    ]
)
