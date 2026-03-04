// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Spore1",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Spore1",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Spore1"
        ),
    ]
)
