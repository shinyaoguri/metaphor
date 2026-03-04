// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WidthHeight",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "WidthHeight",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "WidthHeight"
        ),
    ]
)
