// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "CircleCollision",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CircleCollision",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CircleCollision"
        ),
    ]
)
