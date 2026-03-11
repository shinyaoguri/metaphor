// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Directional",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Directional",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Directional"
        ),
    ]
)
