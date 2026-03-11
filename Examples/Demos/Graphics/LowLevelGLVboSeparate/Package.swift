// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LowLevelGLVboSeparate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LowLevelGLVboSeparate",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LowLevelGLVboSeparate"
        ),
    ]
)
