// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "GetChild",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "GetChild",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "GetChild"
        ),
    ]
)
