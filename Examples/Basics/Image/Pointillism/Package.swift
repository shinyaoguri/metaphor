// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Pointillism",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Pointillism",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Pointillism"
        ),
    ]
)
