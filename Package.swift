// swift-tools-version: 6.0

import PackageDescription
import Foundation

let localFrameworkPath = "Frameworks/Syphon.xcframework"
let useLocalSyphon = FileManager.default.fileExists(atPath: localFrameworkPath)

let syphonTarget: Target = useLocalSyphon
    ? .binaryTarget(name: "Syphon", path: localFrameworkPath)
    : .binaryTarget(
        name: "Syphon",
        url: "https://github.com/shinyaoguri/metaphor/releases/download/v0.1.0/Syphon.xcframework.zip",
        checksum: "PLACEHOLDER_CHECKSUM"
    )

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
        syphonTarget,
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
