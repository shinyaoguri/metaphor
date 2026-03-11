// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Translate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Translate",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Translate"
        ),
    ]
)
