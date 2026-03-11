// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Reach1",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Reach1",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Reach1"
        ),
    ]
)
