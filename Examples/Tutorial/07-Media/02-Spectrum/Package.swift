// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Spectrum",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Spectrum",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Spectrum"
        ),
    ]
)
