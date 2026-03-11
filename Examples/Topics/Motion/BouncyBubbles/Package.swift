// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "BouncyBubbles",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BouncyBubbles",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "BouncyBubbles"
        ),
    ]
)
