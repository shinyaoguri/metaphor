// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Mouse1D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Mouse1D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Mouse1D"
        ),
    ]
)
