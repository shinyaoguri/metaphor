// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PolygonPShapeOOP2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PolygonPShapeOOP2",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PolygonPShapeOOP2"
        ),
    ]
)
