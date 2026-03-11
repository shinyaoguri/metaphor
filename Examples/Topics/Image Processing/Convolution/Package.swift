// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Convolution",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Convolution",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Convolution"
        ),
    ]
)
