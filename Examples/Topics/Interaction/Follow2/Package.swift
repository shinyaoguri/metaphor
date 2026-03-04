// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Follow2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Follow2",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Follow2"
        ),
    ]
)
