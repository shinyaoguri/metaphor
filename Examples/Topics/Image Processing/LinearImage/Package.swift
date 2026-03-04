// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LinearImage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LinearImage",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LinearImage"
        ),
    ]
)
