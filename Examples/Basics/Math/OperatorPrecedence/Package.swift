// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OperatorPrecedence",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "OperatorPrecedence",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "OperatorPrecedence"
        ),
    ]
)
