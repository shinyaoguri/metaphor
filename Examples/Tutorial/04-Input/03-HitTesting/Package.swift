// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "HitTesting",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "HitTesting",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "HitTesting"
        ),
    ]
)
