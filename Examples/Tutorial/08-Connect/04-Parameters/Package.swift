// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Parameters",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Parameters",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Parameters"
        ),
    ]
)
