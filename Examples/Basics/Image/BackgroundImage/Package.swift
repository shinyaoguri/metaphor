// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BackgroundImage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BackgroundImage",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "BackgroundImage"
        ),
    ]
)
