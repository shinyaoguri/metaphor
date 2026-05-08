// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ProbeSnapshot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ProbeSnapshot",
            dependencies: [
                .product(name: "metaphor", package: "metaphor"),
            ],
            path: "ProbeSnapshot"
        ),
    ]
)
