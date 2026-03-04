// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MultipleConstructors",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MultipleConstructors",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MultipleConstructors"
        ),
    ]
)
