// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Mixture",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Mixture",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Mixture"
        ),
    ]
)
