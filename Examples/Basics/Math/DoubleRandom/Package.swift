// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "DoubleRandom",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DoubleRandom",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DoubleRandom"
        ),
    ]
)
