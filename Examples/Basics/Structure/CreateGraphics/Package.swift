// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CreateGraphics",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CreateGraphics",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CreateGraphics"
        ),
    ]
)
