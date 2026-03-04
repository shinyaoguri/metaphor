// swift-tools-version: 6.0
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
