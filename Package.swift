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
        url: "https://github.com/shinyaoguri/metaphor/releases/download/v0.4.0/Syphon.xcframework.zip",
        checksum: "a1609b8b5f7ff16bf94c452e92cc211bcb05b28cdf33d4c54e946d5524cf5753"
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
        .library(name: "MetaphorVideo", targets: ["MetaphorVideo"]),
        .library(name: "MetaphorSyphon", targets: ["MetaphorSyphon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        syphonTarget,

        // Core: rendering engine, drawing, sketch protocol, shaders, and all tightly-coupled subsystems.
        // NOTE: Core does NOT depend on Syphon. Frame output (Syphon etc.) lives in separate targets
        // (e.g. MetaphorSyphon) and registers itself via MetaphorOutputRegistry at load time. See ADR.
        .target(
            name: "MetaphorCore",
            resources: [
                .copy("Shaders/Metal"),
                .copy("Shaders/ShaderSources"),
            ]
        ),

        // Syphon frame output, split out of MetaphorCore (Issue #73 / ADR). Owns the Syphon binaryTarget.
        // The C bootstrap target runs an __attribute__((constructor)) at load that registers the output
        // factory, so `import metaphor` users get transparent Syphon output without referencing this module.
        .target(name: "CMetaphorSyphonBootstrap"),
        .target(
            name: "MetaphorSyphon",
            dependencies: [
                "MetaphorCore",
                "Syphon",
                "CMetaphorSyphonBootstrap",
            ]
        ),

        // Tier 1 modules: zero dependency on MetaphorCore
        .target(name: "MetaphorAudio"),
        .target(name: "MetaphorNetwork"),
        .target(name: "MetaphorPhysics"),
        .target(name: "MetaphorML"),
        .target(name: "MetaphorVideo"),

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
                "MetaphorVideo",
                "MetaphorNoise",
                "MetaphorMPS",
                "MetaphorCoreImage",
                "MetaphorRenderGraph",
                "MetaphorSceneGraph",
                "MetaphorSyphon",
            ]
        ),

        // Test support (internal only, not a published product)
        .target(name: "MetaphorTestSupport", dependencies: ["MetaphorCore"]),

        // Tests
        .testTarget(name: "MetaphorAudioTests", dependencies: ["MetaphorAudio"]),
        .testTarget(name: "MetaphorNetworkTests", dependencies: ["MetaphorNetwork"]),
        .testTarget(name: "MetaphorPhysicsTests", dependencies: ["MetaphorPhysics"]),
        .testTarget(name: "MetaphorMLTests", dependencies: ["MetaphorML"]),
        .testTarget(name: "MetaphorVideoTests", dependencies: ["MetaphorVideo"]),
        .testTarget(name: "MetaphorNoiseTests", dependencies: ["MetaphorNoise"]),
        .testTarget(name: "MetaphorMPSTests", dependencies: ["MetaphorMPS", "MetaphorCore"]),
        .testTarget(name: "MetaphorCoreImageTests", dependencies: ["MetaphorCoreImage"]),
        .testTarget(name: "MetaphorRenderGraphTests", dependencies: ["MetaphorRenderGraph", "MetaphorCore"]),
        .testTarget(name: "MetaphorSceneGraphTests", dependencies: ["MetaphorSceneGraph", "MetaphorCore"]),
        .testTarget(name: "metaphorTests", dependencies: ["metaphor", "MetaphorTestSupport"]),
    ]
)
