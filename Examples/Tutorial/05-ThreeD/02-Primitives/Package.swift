// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Primitives",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Primitives",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Primitives"
        ),
    ]
)
