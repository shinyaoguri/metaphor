// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DomeProjection",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DomeProjection",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DomeProjection"
        ),
    ]
)
