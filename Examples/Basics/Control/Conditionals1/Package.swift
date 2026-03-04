// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Conditionals1",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Conditionals1",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Conditionals1"
        ),
    ]
)
