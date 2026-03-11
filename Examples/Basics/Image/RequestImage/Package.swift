// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "RequestImage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RequestImage",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RequestImage",
            resources: [.copy("Resources")]
        ),
    ]
)
