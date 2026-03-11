// swift-tools-version: 5.10
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
