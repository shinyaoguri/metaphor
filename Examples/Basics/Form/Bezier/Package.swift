// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Bezier",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Bezier",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Bezier"
        ),
    ]
)
