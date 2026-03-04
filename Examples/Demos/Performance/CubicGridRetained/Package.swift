// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CubicGridRetained",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CubicGridRetained",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CubicGridRetained"
        ),
    ]
)
