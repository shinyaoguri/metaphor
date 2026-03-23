// swift-tools-version: 5.10

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
        url: "https://github.com/shinyaoguri/metaphor/releases/download/v0.2.1/Syphon.xcframework.zip",
        checksum: "dfed7fcf2165b519316152c0cc6d2b7b6104a2440132628b9ce5aa2ba5b6093b"
    )

let package = Package(
    name: "metaphor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "metaphor", targets: ["metaphor"]),
        .library(name: "MetaphorCore", targets: ["MetaphorCore"]),
        .library(name: "MetaphorAudio", targets: ["MetaphorAudio"]),
        .library(name: "MetaphorNetwork", targets: ["MetaphorNetwork"]),
        .library(name: "MetaphorPhysics", targets: ["MetaphorPhysics"]),
        .library(name: "MetaphorML", targets: ["MetaphorML"]),
        .library(name: "MetaphorNoise", targets: ["MetaphorNoise"]),
        .library(name: "MetaphorMPS", targets: ["MetaphorMPS"]),
        .library(name: "MetaphorCoreImage", targets: ["MetaphorCoreImage"]),
        .library(name: "MetaphorRenderGraph", targets: ["MetaphorRenderGraph"]),
        .library(name: "MetaphorSceneGraph", targets: ["MetaphorSceneGraph"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        syphonTarget,

        // Core: rendering engine, drawing, sketch protocol, shaders, and all tightly-coupled subsystems
        .target(
            name: "MetaphorCore",
            dependencies: [
                "Syphon"
            ],
            resources: [
                .copy("Shaders/Metal"),
                .copy("Shaders/ShaderSources"),
            ]
        ),

        // Tier 1 modules: zero dependency on MetaphorCore
        .target(name: "MetaphorAudio"),
        .target(name: "MetaphorNetwork"),
        .target(name: "MetaphorPhysics"),
        .target(name: "MetaphorML"),

        // Tier 2 modules: depend on MetaphorCore
        .target(name: "MetaphorNoise", dependencies: ["MetaphorCore"]),
        .target(name: "MetaphorMPS", dependencies: ["MetaphorCore"]),
        .target(name: "MetaphorCoreImage", dependencies: ["MetaphorCore"]),
        .target(name: "MetaphorRenderGraph", dependencies: ["MetaphorCore"]),
        .target(name: "MetaphorSceneGraph", dependencies: ["MetaphorCore"]),

        // Umbrella: re-exports everything for backward compatibility
        .target(
            name: "metaphor",
            dependencies: [
                "MetaphorCore",
                "MetaphorAudio",
                "MetaphorNetwork",
                "MetaphorPhysics",
                "MetaphorML",
                "MetaphorNoise",
                "MetaphorMPS",
                "MetaphorCoreImage",
                "MetaphorRenderGraph",
                "MetaphorSceneGraph",
            ]
        ),

        // Test support (internal only, not a published product)
        .target(name: "MetaphorTestSupport", dependencies: ["MetaphorCore"]),

        // Tests
        .testTarget(name: "MetaphorAudioTests", dependencies: ["MetaphorAudio"]),
        .testTarget(name: "MetaphorNetworkTests", dependencies: ["MetaphorNetwork"]),
        .testTarget(name: "MetaphorPhysicsTests", dependencies: ["MetaphorPhysics"]),
        .testTarget(name: "MetaphorMLTests", dependencies: ["MetaphorML"]),
        .testTarget(name: "MetaphorNoiseTests", dependencies: ["MetaphorNoise"]),
        .testTarget(name: "MetaphorMPSTests", dependencies: ["MetaphorMPS", "MetaphorCore"]),
        .testTarget(name: "MetaphorCoreImageTests", dependencies: ["MetaphorCoreImage"]),
        .testTarget(name: "MetaphorRenderGraphTests", dependencies: ["MetaphorRenderGraph", "MetaphorCore"]),
        .testTarget(name: "MetaphorSceneGraphTests", dependencies: ["MetaphorSceneGraph", "MetaphorCore"]),
        .testTarget(name: "metaphorTests", dependencies: ["metaphor", "MetaphorTestSupport"]),
    ]
)
