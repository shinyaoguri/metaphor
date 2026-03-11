// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Random",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Random",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Random"
        ),
    ]
)
