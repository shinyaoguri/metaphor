// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LoadDisplayOBJ",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LoadDisplayOBJ",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LoadDisplayOBJ",
            resources: [.copy("Resources")]
        ),
    ]
)
