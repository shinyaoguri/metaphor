// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Explode",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Explode",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Explode"
        ),
    ]
)
