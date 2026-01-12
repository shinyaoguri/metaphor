// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BasicShapes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "BasicShapes",
            dependencies: ["metaphor"],
            path: "BasicShapes"
        ),
    ]
)
