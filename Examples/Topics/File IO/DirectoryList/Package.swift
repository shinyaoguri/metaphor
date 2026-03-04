// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DirectoryList",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DirectoryList",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DirectoryList"
        ),
    ]
)
