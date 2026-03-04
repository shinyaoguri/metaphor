// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Wiggling",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Wiggling",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Wiggling"
        ),
    ]
)
