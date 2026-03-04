// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MultipleWindows",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MultipleWindows",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MultipleWindows"
        ),
    ]
)
