// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "GlossyFishEye",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "GlossyFishEye",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "GlossyFishEye"
        ),
    ]
)
