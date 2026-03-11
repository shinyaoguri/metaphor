// swift-tools-version: 5.10
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
