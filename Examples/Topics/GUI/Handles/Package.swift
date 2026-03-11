// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Handles",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Handles",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Handles"
        ),
    ]
)
