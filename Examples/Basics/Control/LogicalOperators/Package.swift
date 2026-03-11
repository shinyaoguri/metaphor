// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LogicalOperators",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LogicalOperators",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LogicalOperators"
        ),
    ]
)
