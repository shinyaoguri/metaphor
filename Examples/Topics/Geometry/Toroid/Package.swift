// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Toroid",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Toroid",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Toroid"
        ),
    ]
)
