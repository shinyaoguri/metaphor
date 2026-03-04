// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CharactersStrings",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "CharactersStrings",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "CharactersStrings"
        ),
    ]
)
