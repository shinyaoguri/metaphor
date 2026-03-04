// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Relativity",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Relativity",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Relativity"
        ),
    ]
)
