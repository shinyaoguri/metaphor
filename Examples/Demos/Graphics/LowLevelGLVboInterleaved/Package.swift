// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LowLevelGLVboInterleaved",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "LowLevelGLVboInterleaved",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "LowLevelGLVboInterleaved"
        ),
    ]
)
