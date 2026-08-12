// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PostProcess",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PostProcess",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PostProcess"
        ),
    ]
)
