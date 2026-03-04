// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeginEndContour",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BeginEndContour",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "BeginEndContour"
        ),
    ]
)
