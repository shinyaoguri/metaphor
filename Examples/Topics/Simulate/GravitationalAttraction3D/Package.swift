// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "GravitationalAttraction3D",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "GravitationalAttraction3D",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "GravitationalAttraction3D"
        ),
    ]
)
