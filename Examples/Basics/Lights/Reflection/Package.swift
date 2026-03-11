// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Reflection",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Reflection",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Reflection"
        ),
    ]
)
