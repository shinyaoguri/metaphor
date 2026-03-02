// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FilterGallery",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "metaphor", path: "../../../.."),
    ],
    targets: [
        .executableTarget(
            name: "FilterGallery",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ],
            path: "FilterGallery"
        ),
    ]
)
