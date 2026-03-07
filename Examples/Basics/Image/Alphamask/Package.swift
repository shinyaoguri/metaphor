// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Alphamask",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Alphamask",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Alphamask",
            resources: [.copy("Resources")]
        ),
    ]
)
