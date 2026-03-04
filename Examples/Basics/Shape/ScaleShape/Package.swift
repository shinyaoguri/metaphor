// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ScaleShape",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ScaleShape",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ScaleShape"
        ),
    ]
)
