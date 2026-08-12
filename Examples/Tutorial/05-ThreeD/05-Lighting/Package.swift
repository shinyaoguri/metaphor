// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Lighting",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Lighting",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Lighting"
        ),
    ]
)
