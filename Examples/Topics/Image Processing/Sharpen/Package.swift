// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Sharpen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Sharpen",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Sharpen"
        ),
    ]
)
