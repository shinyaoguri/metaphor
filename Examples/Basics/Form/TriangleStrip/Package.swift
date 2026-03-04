// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TriangleStrip",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TriangleStrip",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TriangleStrip"
        ),
    ]
)
