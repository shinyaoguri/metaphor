// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ManyObjects",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ManyObjects",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ManyObjects"
        ),
    ]
)
