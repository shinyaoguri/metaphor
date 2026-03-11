// swift-tools-version: 5.10
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
