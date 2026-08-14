// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Trigonometry",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Trigonometry",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Trigonometry"
        ),
    ]
)
