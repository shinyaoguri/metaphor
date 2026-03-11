// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LoadFile2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LoadFile2",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LoadFile2"
        ),
    ]
)
