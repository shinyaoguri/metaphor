// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Recursion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Recursion",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Recursion"
        ),
    ]
)
