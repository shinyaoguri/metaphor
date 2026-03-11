// swift-tools-version: 5.10
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
