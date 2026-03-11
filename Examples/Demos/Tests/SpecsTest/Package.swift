// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpecsTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SpecsTest",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SpecsTest"
        ),
    ]
)
