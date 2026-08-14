// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "CustomPostEffect",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CustomPostEffect",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CustomPostEffect"
        ),
    ]
)
