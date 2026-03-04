// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Pattern",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Pattern",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Pattern"
        ),
    ]
)
