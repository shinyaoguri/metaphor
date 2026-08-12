// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MIDI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MIDI",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MIDI"
        ),
    ]
)
