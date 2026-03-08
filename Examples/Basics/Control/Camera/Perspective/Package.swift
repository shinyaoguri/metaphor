// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Perspective",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Perspective",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Perspective"
        ),
    ]
)
