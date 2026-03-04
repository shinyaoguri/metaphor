// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PolarToCartesian",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PolarToCartesian",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PolarToCartesian"
        ),
    ]
)
