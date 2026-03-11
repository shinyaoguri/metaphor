// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Vertices",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Vertices",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Vertices"
        ),
    ]
)
