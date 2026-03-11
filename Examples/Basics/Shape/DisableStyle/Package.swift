// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "DisableStyle",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DisableStyle",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DisableStyle"
        ),
    ]
)
