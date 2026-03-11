// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "DatatypeConversion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "DatatypeConversion",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "DatatypeConversion"
        ),
    ]
)
