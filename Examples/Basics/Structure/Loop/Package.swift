// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Loop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Loop",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Loop"
        ),
    ]
)
