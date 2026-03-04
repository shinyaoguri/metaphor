// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BouncingBall",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BouncingBall",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "BouncingBall"
        ),
    ]
)
