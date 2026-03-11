// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MousePress",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MousePress",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MousePress"
        ),
    ]
)
