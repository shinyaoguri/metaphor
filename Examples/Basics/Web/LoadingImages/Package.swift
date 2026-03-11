// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LoadingImages",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LoadingImages",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LoadingImages"
        ),
    ]
)
