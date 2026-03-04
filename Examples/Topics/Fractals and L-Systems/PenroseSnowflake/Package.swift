// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PenroseSnowflake",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PenroseSnowflake",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PenroseSnowflake"
        ),
    ]
)
