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
        checksum: "a8207f6fd6823515de864582f39794b5e7cc013de69a8f5f5428b1921a2a03f2"
    )

let package = Package(
    name: "metaphor",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
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
            dependencies: [
                .target(name: "Syphon", condition: .when(platforms: [.macOS]))
            ],
            resources: [.process("Shaders/Metal")]
        ),
        .testTarget(
            name: "metaphorTests",
            dependencies: ["metaphor"]
        ),
    ]
)
