// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Map",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Map",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Map"
        ),
    ]
)
