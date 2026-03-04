// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CubesWithinCube",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CubesWithinCube",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CubesWithinCube"
        ),
    ]
)
