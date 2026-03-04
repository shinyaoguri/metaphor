// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RGBCube",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RGBCube",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RGBCube"
        ),
    ]
)
