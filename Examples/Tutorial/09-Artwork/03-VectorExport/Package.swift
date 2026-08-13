// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "VectorExport",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "VectorExport",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "VectorExport"
        ),
    ]
)
