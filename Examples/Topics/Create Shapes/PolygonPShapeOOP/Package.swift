// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PolygonPShapeOOP",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PolygonPShapeOOP",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PolygonPShapeOOP"
        ),
    ]
)
