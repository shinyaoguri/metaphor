// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CreateImage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CreateImage",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CreateImage"
        ),
    ]
)
