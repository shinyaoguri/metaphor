// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TextRotation",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TextRotation",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TextRotation"
        ),
    ]
)
