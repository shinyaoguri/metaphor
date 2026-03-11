// swift-tools-version: 5.10
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
