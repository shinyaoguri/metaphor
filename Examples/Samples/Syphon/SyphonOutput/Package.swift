// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SyphonOutput",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SyphonOutput",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SyphonOutput"
        ),
    ]
)
