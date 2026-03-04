// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ArrayObjects",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ArrayObjects",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ArrayObjects"
        ),
    ]
)
