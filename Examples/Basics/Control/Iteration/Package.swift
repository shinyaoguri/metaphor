// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Iteration",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Iteration",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Iteration"
        ),
    ]
)
