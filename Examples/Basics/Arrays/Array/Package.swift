// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Array",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Array",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Array"
        ),
    ]
)
