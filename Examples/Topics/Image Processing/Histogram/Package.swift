// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Histogram",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Histogram",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Histogram"
        ),
    ]
)
