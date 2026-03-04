// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Button",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Button",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Button"
        ),
    ]
)
