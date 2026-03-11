// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "StatementsComments",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "StatementsComments",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "StatementsComments"
        ),
    ]
)
