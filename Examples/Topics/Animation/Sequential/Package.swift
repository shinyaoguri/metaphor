// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sequential",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Sequential",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Sequential"
        ),
    ]
)
