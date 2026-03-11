// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "EmbeddedLinks",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "EmbeddedLinks",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "EmbeddedLinks"
        ),
    ]
)
