// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Mandelbrot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "Mandelbrot",
            dependencies: [.product(name: "metaphor", package: "metaphor")],
            path: "Mandelbrot"
        ),
    ]
)
