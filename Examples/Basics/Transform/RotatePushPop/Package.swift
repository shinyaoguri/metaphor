// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "RotatePushPop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RotatePushPop",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RotatePushPop"
        ),
    ]
)
