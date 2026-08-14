// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "DrawControl",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DrawControl",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DrawControl"
        ),
    ]
)
