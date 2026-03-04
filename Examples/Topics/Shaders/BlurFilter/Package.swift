// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BlurFilter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BlurFilter",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "BlurFilter"
        ),
    ]
)
