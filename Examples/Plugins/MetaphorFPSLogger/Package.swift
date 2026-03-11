// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MetaphorFPSLogger",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetaphorFPSLogger", targets: ["MetaphorFPSLogger"]),
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .target(
            name: "MetaphorFPSLogger",
            dependencies: [.product(name: "MetaphorCore", package: "metaphor")],
            path: "Sources"
        ),
    ]
)
