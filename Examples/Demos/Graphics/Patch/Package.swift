// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Patch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Patch",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Patch"
        ),
    ]
)
