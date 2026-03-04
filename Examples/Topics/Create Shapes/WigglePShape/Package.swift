// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WigglePShape",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "WigglePShape",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "WigglePShape"
        ),
    ]
)
