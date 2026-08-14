// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ParameterPanel",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ParameterPanel",
            dependencies: [
                .product(name: "metaphor", package: "metaphor"),
            ],
            path: "ParameterPanel"
        ),
    ]
)
