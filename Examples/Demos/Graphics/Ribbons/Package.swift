// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Ribbons",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Ribbons",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Ribbons"
        ),
    ]
)
