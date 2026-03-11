// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Scrollbar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Scrollbar",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Scrollbar"
        ),
    ]
)
