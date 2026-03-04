// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MouseFunctions",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "MouseFunctions",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "MouseFunctions"
        ),
    ]
)
