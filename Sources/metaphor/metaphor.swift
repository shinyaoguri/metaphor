/// Processing、p5.js、openFrameworks にインスパイアされた Swift + Metal クリエイティブコーディングライブラリ。
///
/// `metaphor` をインポートすると、オーディオ、ネットワーク、物理、
/// その他のオプションサブシステムモジュールを含むフルライブラリにアクセスできます。
/// 最小限のビルドには、代わりに `MetaphorCore` をインポートしてください。

@_exported import MetaphorAudio
@_exported import MetaphorCore
@_exported import MetaphorCoreImage
@_exported import MetaphorML
@_exported import MetaphorMPS
@_exported import MetaphorNetwork
@_exported import MetaphorNoise
@_exported import MetaphorPhysics
@_exported import MetaphorRenderGraph
@_exported import MetaphorSceneGraph
@_exported import MetaphorVideo
// Syphon は別パッケージ `metaphor-syphon`（ADR-0014）。`Package.swift` に足して `import MetaphorSyphon` する。
