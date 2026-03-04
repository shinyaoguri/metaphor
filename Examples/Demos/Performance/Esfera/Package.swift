// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Esfera",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Esfera",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Esfera"
        ),
    ]
)
