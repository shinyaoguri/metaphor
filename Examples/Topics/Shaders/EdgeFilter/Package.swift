// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "EdgeFilter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "EdgeFilter",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "EdgeFilter"
        ),
    ]
)
