// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RotateXY",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RotateXY",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RotateXY"
        ),
    ]
)
