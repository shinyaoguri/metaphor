// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Zoom",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Zoom",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Zoom"
        ),
    ]
)
