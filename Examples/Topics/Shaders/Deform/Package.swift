// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Deform",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Deform",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Deform"
        ),
    ]
)
