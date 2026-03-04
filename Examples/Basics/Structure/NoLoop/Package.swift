// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NoLoop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "NoLoop",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "NoLoop"
        ),
    ]
)
