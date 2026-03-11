// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Follow1",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Follow1",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Follow1"
        ),
    ]
)
