// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CountingStrings",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CountingStrings",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CountingStrings"
        ),
    ]
)
