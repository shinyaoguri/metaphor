// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SaveFile2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SaveFile2",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SaveFile2"
        ),
    ]
)
