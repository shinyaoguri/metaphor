// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "OnOff",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "OnOff",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "OnOff"
        ),
    ]
)
