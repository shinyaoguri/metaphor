// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Sine",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Sine",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Sine"
        ),
    ]
)
