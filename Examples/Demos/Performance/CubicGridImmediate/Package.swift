// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CubicGridImmediate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CubicGridImmediate",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CubicGridImmediate"
        ),
    ]
)
