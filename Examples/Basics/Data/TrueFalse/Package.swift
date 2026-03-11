// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "TrueFalse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "TrueFalse",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "TrueFalse"
        ),
    ]
)
