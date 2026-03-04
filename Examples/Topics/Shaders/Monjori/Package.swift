// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Monjori",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Monjori",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Monjori"
        ),
    ]
)
