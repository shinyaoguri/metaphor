// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Words",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Words",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Words"
        ),
    ]
)
