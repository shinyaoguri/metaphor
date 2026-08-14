// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Compute",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Compute",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Compute"
        ),
    ]
)
