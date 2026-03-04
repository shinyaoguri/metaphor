// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Orthographic",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Orthographic",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Orthographic"
        ),
    ]
)
