// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SaveOneImage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SaveOneImage",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SaveOneImage"
        ),
    ]
)
