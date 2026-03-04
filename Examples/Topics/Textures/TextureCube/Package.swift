// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TextureCube",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TextureCube",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TextureCube"
        ),
    ]
)
