// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Extrusion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Extrusion",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Extrusion"
        ),
    ]
)
