// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Conditionals2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Conditionals2",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Conditionals2"
        ),
    ]
)
