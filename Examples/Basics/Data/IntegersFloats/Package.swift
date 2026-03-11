// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "IntegersFloats",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "IntegersFloats",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "IntegersFloats"
        ),
    ]
)
