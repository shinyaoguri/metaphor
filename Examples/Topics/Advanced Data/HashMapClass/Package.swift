// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HashMapClass",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "HashMapClass",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "HashMapClass"
        ),
    ]
)
