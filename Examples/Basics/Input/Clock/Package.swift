// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Clock",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Clock",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Clock"
        ),
    ]
)
