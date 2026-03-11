// swift-tools-version: 5.10
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
