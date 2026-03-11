// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "GetTessGroups",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "GetTessGroups",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "GetTessGroups"
        ),
    ]
)
