// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SoftBody",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SoftBody",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SoftBody"
        ),
    ]
)
