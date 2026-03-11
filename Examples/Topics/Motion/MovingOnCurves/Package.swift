// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MovingOnCurves",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MovingOnCurves",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MovingOnCurves"
        ),
    ]
)
