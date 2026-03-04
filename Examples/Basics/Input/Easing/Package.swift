// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Easing",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Easing",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Easing"
        ),
    ]
)
