// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "TextureSphere",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TextureSphere",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TextureSphere"
        ),
    ]
)
