// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VariableScope",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "VariableScope",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "VariableScope"
        ),
    ]
)
