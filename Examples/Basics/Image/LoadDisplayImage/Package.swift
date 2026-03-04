// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LoadDisplayImage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LoadDisplayImage",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LoadDisplayImage"
        ),
    ]
)
