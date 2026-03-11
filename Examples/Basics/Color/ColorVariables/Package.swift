// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ColorVariables",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ColorVariables",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ColorVariables"
        ),
    ]
)
