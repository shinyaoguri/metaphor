// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Reach3",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Reach3",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Reach3"
        ),
    ]
)
