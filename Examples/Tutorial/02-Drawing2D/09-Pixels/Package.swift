// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Pixels",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Pixels",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Pixels"
        ),
    ]
)
