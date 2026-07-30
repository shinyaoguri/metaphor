// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "OSCLoopback",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "OSCLoopback",
            dependencies: [
                .product(name: "metaphor", package: "metaphor"),
            ],
            path: "OSCLoopback"
        ),
    ]
)
