// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MetaphorMouseTrail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetaphorMouseTrail", targets: ["MetaphorMouseTrail"]),
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .target(
            name: "MetaphorMouseTrail",
            dependencies: [.product(name: "MetaphorCore", package: "metaphor")],
            path: "Sources"
        ),
    ]
)
