// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Blur",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Blur",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Blur"
        ),
    ]
)
