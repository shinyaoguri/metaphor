// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SetupDraw",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SetupDraw",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SetupDraw"
        ),
    ]
)
