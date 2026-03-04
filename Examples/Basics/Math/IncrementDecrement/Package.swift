// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "IncrementDecrement",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "IncrementDecrement",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "IncrementDecrement"
        ),
    ]
)
