// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Blending",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Blending",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Blending"
        ),
    ]
)
