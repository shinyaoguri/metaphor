// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Mouse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Mouse",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Mouse"
        ),
    ]
)
