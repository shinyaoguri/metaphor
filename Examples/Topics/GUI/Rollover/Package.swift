// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Rollover",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Rollover",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Rollover"
        ),
    ]
)
