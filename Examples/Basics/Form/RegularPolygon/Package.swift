// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "RegularPolygon",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "RegularPolygon",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "RegularPolygon"
        ),
    ]
)
