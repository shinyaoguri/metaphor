// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BrightnessPixels",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BrightnessPixels",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "BrightnessPixels"
        ),
    ]
)
