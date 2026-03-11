// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Reach2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Reach2",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Reach2"
        ),
    ]
)
