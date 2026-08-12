// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Material",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Material",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Material"
        ),
    ]
)
