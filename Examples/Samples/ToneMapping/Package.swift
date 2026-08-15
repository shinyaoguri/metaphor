// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ToneMapping",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ToneMapping",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ToneMapping"
        ),
    ]
)
