// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Brownian",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Brownian",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Brownian"
        ),
    ]
)
