// swift-tools-version: 5.10

import PackageDescription
import Foundation

// Get the directory containing this Package.swift
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let localFrameworkPath = "Frameworks/Syphon.xcframework"
let absoluteFrameworkPath = packageDir + "/" + localFrameworkPath
let useLocalSyphon = FileManager.default.fileExists(atPath: absoluteFrameworkPath)

// Swift 6 strict concurrency の段階導入（Issue #328）。適用済みのターゲットにだけ
// `swiftSettings: strictConcurrency` を付ける。未適用のターゲットは従来どおり。
//
// swift-tools-version は 5.10 のままなので言語モードは Swift 5 = 診断は **警告**
// であり、ビルドは落ちない（`-warnings-as-errors` を付けている build-and-test でも
// 落ちないよう、適用は警告ゼロを確認したターゲットに限る）。
//
// 綴りをツールチェーンで振り分ける理由（実測は Issue #328 のコメント参照）:
//   - Swift 6.0+ では StrictConcurrency は *upcoming* feature。`.enableUpcomingFeature`
//     が正規の綴り。
//   - 最小サポートの Swift 5.10（Xcode 15.4 / 必須チェック build-swift-5-10）では
//     まだ *experimental* feature。5.10 に upcoming 名で渡しても黙って無視され、
//     チェックが効かない。
// `.unsafeFlags(["-strict-concurrency=complete"])` は挙動こそ同じだが、版指定で
// 依存された瞬間に SwiftPM が解決を拒否する（ライブラリでは採用不可）。
#if compiler(>=6.0)
let strictConcurrency: [SwiftSetting] = [.enableUpcomingFeature("StrictConcurrency")]
#else
let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]
#endif

let syphonTarget: Target = useLocalSyphon
    ? .binaryTarget(name: "Syphon", path: localFrameworkPath)
    : .binaryTarget(
        name: "Syphon",
        url: "https://github.com/shinyaoguri/metaphor/releases/download/v0.8.0/Syphon.xcframework.zip",
        checksum: "a79ccfc34c090e4fa029a3202a4c689bb38c0e150ef92b164b5c354b71c06c39"
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
    // 外部依存なし。ドキュメント生成は `xcrun docc` を直接呼ぶ（Makefile / docs.yml）ため
    // swift-docc-plugin は不要（ライブラリ利用者の resolve 時 fetch を増やさない）。
    dependencies: [],
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
            ],
            swiftSettings: strictConcurrency
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
            ],
            swiftSettings: strictConcurrency
        ),

        // Tier 1 modules: zero dependency on MetaphorCore.
        // strict concurrency 適用済み（Issue #328 段階 2）。Core / Tier 2 は段階 3。
        .target(name: "MetaphorAudio", swiftSettings: strictConcurrency),
        .target(name: "MetaphorNetwork", swiftSettings: strictConcurrency),
        .target(name: "MetaphorPhysics", swiftSettings: strictConcurrency),
        .target(name: "MetaphorML", swiftSettings: strictConcurrency),
        .target(name: "MetaphorVideo", swiftSettings: strictConcurrency),

        // Tier 2 modules: depend on MetaphorCore
        .target(name: "MetaphorNoise", dependencies: ["MetaphorCore"], swiftSettings: strictConcurrency),
        .target(name: "MetaphorMPS", dependencies: ["MetaphorCore"], swiftSettings: strictConcurrency),
        .target(name: "MetaphorCoreImage", dependencies: ["MetaphorCore"], swiftSettings: strictConcurrency),
        .target(name: "MetaphorRenderGraph", dependencies: ["MetaphorCore"], swiftSettings: strictConcurrency),
        .target(name: "MetaphorSceneGraph", dependencies: ["MetaphorCore"], swiftSettings: strictConcurrency),

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
            ],
            swiftSettings: strictConcurrency
        ),

        // Test support (internal only, not a published product)
        .target(name: "MetaphorTestSupport", dependencies: ["MetaphorCore"], swiftSettings: strictConcurrency),

        // Tests
        // Tier 1 のテストも本体と同じ設定で建てる（テスト側から非 Sendable な
        // 使い方が再流入するのを防ぐ）。
        .testTarget(
            name: "MetaphorAudioTests", dependencies: ["MetaphorAudio"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorNetworkTests", dependencies: ["MetaphorNetwork"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorPhysicsTests", dependencies: ["MetaphorPhysics"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorMLTests", dependencies: ["MetaphorML"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorVideoTests", dependencies: ["MetaphorVideo"],
            swiftSettings: strictConcurrency),
        .testTarget(name: "MetaphorNoiseTests", dependencies: ["MetaphorNoise"], swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorMPSTests", dependencies: ["MetaphorMPS", "MetaphorCore"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorCoreImageTests", dependencies: ["MetaphorCoreImage"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorRenderGraphTests", dependencies: ["MetaphorRenderGraph", "MetaphorCore"],
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "MetaphorSceneGraphTests", dependencies: ["MetaphorSceneGraph", "MetaphorCore"],
            swiftSettings: strictConcurrency),
        // Golden/ はテストバンドルへコピーせず除外する。ゴールデン PNG は
        // `#filePath` からソースツリーを直接読み書きする（Issue #330）ため、
        // リソースとして同梱する必要がない（宣言しないと SwiftPM が
        // "unhandled files" 警告を出す）。
        .testTarget(
            name: "metaphorTests",
            dependencies: ["metaphor", "MetaphorTestSupport"],
            exclude: ["Golden"],
            swiftSettings: strictConcurrency
        ),
    ]
)
