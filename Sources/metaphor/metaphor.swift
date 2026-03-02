/// A Swift + Metal creative coding library inspired by Processing, p5.js, and openFrameworks.
///
/// metaphor provides an immediate-mode creative coding environment powered by Metal.
/// Implement the ``Sketch`` protocol to get started — the library handles window creation,
/// Metal device setup, and the render loop automatically.
///
/// ```swift
/// import metaphor
///
/// @main
/// final class MySketch: Sketch {
///     func setup() {
///         size(1280, 720)
///     }
///
///     func draw() {
///         background(0.1)
///         fill(Color.white)
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```

@_exported import Metal
@_exported import MetalKit
@_exported import simd
#if os(macOS)
@_exported import Syphon
#endif
