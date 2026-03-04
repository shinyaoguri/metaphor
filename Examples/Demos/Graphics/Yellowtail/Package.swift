// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yellowtail",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Yellowtail",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Yellowtail"
        ),
    ]
)
