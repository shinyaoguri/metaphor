// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Regex",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Regex",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Regex"
        ),
    ]
)
