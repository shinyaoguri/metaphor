// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Constrain",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Constrain",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Constrain"
        ),
    ]
)
