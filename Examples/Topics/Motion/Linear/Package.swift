// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Linear",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Linear",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Linear"
        ),
    ]
)
