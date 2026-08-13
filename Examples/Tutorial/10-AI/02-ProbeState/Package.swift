// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ProbeState",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ProbeState",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ProbeState"
        ),
    ]
)
