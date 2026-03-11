// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ImageMask",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ImageMask",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ImageMask"
        ),
    ]
)
