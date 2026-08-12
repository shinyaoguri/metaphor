// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Keyboard",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Keyboard",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Keyboard"
        ),
    ]
)
