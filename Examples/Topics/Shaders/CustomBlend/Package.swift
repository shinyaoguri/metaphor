// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "CustomBlend",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CustomBlend",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CustomBlend"
        ),
    ]
)
