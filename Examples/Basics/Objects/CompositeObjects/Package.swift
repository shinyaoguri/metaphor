// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CompositeObjects",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CompositeObjects",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CompositeObjects"
        ),
    ]
)
