// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Brightness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Brightness",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Brightness"
        ),
    ]
)
