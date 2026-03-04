// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PolygonPShape",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PolygonPShape",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PolygonPShape"
        ),
    ]
)
