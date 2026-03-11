// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Pulses",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Pulses",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Pulses"
        ),
    ]
)
