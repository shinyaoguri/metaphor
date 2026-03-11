// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SpaceJunk",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SpaceJunk",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SpaceJunk"
        ),
    ]
)
