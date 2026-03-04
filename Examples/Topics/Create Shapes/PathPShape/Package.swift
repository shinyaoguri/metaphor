// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PathPShape",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PathPShape",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PathPShape"
        ),
    ]
)
