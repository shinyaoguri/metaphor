// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "PolygonPShapeOOP3",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "PolygonPShapeOOP3",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "PolygonPShapeOOP3"
        ),
    ]
)
