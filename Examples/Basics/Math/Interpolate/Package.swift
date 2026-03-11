// swift-tools-version: 5.10
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
