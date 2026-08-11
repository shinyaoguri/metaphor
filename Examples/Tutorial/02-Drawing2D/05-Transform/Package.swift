// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Transform",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Transform",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Transform"
        ),
    ]
)
