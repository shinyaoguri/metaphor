// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MassiveCircles",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MassiveCircles",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MassiveCircles"
        ),
    ]
)
