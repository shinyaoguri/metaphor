// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PluginFPSLogger",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
        .package(name: "MetaphorFPSLogger", path: "../../Plugins/MetaphorFPSLogger"),
    ],
    targets: [
        .executableTarget(
            name: "PluginFPSLogger",
            dependencies: [
                .product(name: "metaphor", package: "metaphor"),
                .product(name: "MetaphorFPSLogger", package: "MetaphorFPSLogger"),
            ],
            path: "PluginFPSLogger"
        ),
    ]
)
