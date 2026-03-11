// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "VectorMath",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "VectorMath",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "VectorMath"
        ),
    ]
)
