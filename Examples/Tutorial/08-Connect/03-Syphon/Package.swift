// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SyphonShare",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SyphonShare",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SyphonShare"
        ),
    ]
)
