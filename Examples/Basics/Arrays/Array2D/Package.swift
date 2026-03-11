// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Array2D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Array2D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Array2D"
        ),
    ]
)
