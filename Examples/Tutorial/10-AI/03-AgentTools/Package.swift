// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "AgentTools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "AgentTools",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "AgentTools"
        ),
    ]
)
