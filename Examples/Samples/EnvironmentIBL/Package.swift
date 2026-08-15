// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "EnvironmentIBL",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "EnvironmentIBL",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "EnvironmentIBL"
        ),
    ]
)
