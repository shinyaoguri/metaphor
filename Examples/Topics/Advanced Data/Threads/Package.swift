// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Threads",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Threads",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Threads"
        ),
    ]
)
