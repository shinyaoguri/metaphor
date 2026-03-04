// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Interpolate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Interpolate",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Interpolate"
        ),
    ]
)
