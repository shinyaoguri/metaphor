// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Trefoil",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Trefoil",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Trefoil"
        ),
    ]
)
