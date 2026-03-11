// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Redraw",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Redraw",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Redraw"
        ),
    ]
)
