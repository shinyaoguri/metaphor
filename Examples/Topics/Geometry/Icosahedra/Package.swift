// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Icosahedra",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Icosahedra",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Icosahedra"
        ),
    ]
)
