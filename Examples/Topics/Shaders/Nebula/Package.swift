// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Nebula",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Nebula",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Nebula"
        ),
    ]
)
