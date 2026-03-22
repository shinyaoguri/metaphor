// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "RayTracing",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RayTracing",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RayTracing"
        ),
    ]
)
