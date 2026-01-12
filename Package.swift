// swift-tools-version: 6.0

import PackageDescription
import Foundation

// Get the directory containing this Package.swift
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let localFrameworkPath = "Frameworks/Syphon.xcframework"
let absoluteFrameworkPath = packageDir + "/" + localFrameworkPath
let useLocalSyphon = FileManager.default.fileExists(atPath: absoluteFrameworkPath)

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
