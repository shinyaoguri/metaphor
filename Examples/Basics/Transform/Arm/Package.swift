// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Arm",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Arm",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Arm"
        ),
    ]
)
