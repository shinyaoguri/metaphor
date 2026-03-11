// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PieChart",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PieChart",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PieChart"
        ),
    ]
)
