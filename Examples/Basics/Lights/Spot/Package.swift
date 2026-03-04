// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Spot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Spot",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Spot"
        ),
    ]
)
