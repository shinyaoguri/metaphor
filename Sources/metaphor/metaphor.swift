/// A Swift + Metal creative coding library inspired by Processing, p5.js and openFrameworks.
///
/// Importing `metaphor` gives you the full library, including the optional
/// subsystem modules for audio, network, physics and more. For a minimal build,
/// import `MetaphorCore` instead.

@_exported import MetaphorCore
@_exported import MetaphorAudio
@_exported import MetaphorNetwork
@_exported import MetaphorPhysics
@_exported import MetaphorML
@_exported import MetaphorVideo
@_exported import MetaphorNoise
@_exported import MetaphorMPS
@_exported import MetaphorCoreImage
@_exported import MetaphorRenderGraph
@_exported import MetaphorSceneGraph
// Syphon は別パッケージ `metaphor-syphon`（ADR-0014）。`Package.swift` に足して `import MetaphorSyphon` する。
