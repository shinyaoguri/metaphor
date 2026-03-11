// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Wolfram",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Wolfram",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Wolfram"
        ),
    ]
)
