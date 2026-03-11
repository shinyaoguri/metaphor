// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PluginMouseTrail",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
        .package(name: "MetaphorMouseTrail", path: "../../Plugins/MetaphorMouseTrail"),
    ],
    targets: [
        .executableTarget(
            name: "PluginMouseTrail",
            dependencies: [
                .product(name: "metaphor", package: "metaphor"),
                .product(name: "MetaphorMouseTrail", package: "MetaphorMouseTrail"),
            ],
            path: "PluginMouseTrail"
        ),
    ]
)
