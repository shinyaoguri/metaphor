// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Inheritance",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Inheritance",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Inheritance"
        ),
    ]
)
