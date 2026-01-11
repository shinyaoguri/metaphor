// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "metaphor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "metaphor",
            targets: ["metaphor"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "Syphon",
            path: "Frameworks/Syphon.xcframework"
        ),
        .target(
            name: "metaphor",
            dependencies: ["Syphon"]
        ),
        .testTarget(
            name: "metaphorTests",
            dependencies: ["metaphor"]
        ),
    ]
)
