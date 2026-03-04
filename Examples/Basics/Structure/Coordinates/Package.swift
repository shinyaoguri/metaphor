// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Coordinates",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Coordinates",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Coordinates"
        ),
    ]
)
