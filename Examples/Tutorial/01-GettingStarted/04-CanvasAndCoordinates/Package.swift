// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "CanvasAndCoordinates",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CanvasAndCoordinates",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CanvasAndCoordinates"
        ),
    ]
)
