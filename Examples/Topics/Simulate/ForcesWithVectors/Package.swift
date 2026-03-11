// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ForcesWithVectors",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ForcesWithVectors",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ForcesWithVectors"
        ),
    ]
)
