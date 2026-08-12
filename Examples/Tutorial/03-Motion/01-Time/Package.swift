// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Time",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Time",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Time"
        ),
    ]
)
