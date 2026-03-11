// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Koch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Koch",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Koch"
        ),
    ]
)
