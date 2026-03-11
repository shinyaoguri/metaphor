// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PenroseTile",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PenroseTile",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PenroseTile"
        ),
    ]
)
