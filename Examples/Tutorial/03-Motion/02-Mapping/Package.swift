// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mapping",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Mapping",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Mapping"
        ),
    ]
)
