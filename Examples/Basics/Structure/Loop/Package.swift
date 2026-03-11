// swift-tools-version: 5.10
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
