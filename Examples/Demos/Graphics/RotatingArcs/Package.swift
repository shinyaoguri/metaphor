// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RotatingArcs",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RotatingArcs",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RotatingArcs"
        ),
    ]
)
