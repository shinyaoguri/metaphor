// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TessUpdate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TessUpdate",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TessUpdate"
        ),
    ]
)
