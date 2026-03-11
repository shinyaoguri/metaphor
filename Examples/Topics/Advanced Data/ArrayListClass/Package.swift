// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ArrayListClass",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ArrayListClass",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "ArrayListClass"
        ),
    ]
)
