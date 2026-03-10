// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SyphonTripleWindow",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SyphonTripleWindow",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SyphonTripleWindow"
        ),
    ]
)
