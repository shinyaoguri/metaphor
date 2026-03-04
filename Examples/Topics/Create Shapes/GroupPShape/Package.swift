// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "GroupPShape",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "GroupPShape",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "GroupPShape"
        ),
    ]
)
