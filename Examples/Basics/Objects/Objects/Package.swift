// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Objects",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Objects",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Objects"
        ),
    ]
)
