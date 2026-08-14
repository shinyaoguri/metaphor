// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "RecordMotion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RecordMotion",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RecordMotion"
        ),
    ]
)
