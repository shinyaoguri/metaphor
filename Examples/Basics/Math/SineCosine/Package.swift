// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "SineCosine",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SineCosine",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "SineCosine"
        ),
    ]
)
