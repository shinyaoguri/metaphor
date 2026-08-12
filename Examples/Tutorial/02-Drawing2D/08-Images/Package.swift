// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Images",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Images",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Images",
            resources: [.copy("Resources")]
        ),
    ]
)
