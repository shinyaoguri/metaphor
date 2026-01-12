// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SketchDemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "SketchDemo",
            dependencies: ["metaphor"],
            path: "SketchDemo"
        ),
    ]
)
