import Foundation

// MARK: - 2D カスタムシェーダ（#647 / Epic #291 E2）

extension Sketch {
    /// Creates a custom 2D fragment shader from MSL source.
    ///
    /// The 2D preamble (``BuiltinShaders/canvas2DPreamble`` = stdlib + struct definitions) is
    /// **always** prepended, so writing just the fragment function is enough.
    /// Do not define `Canvas2DVertexOut` and friends yourself.
    ///
    /// ## The returned color is premultiplied alpha
    ///
    /// The canvas holds colors that have already been multiplied by alpha (ADR-0012). `in.color`
    /// arrives before that multiplication (straight), so **pass the value through the preamble's
    /// `metaphorPremultiply()` right before returning it**.
    ///
    /// ```metal
    /// return metaphorPremultiply(float4(rgb, 1.0) * in.color);
    /// ```
    ///
    /// Forgetting to multiply makes semi-transparent areas look washed out and float above the rest
    /// (a shader that only returns opaque colors leaves the value unchanged, so there is nothing to
    /// worry about if you do not use alpha). On paths that sample a texture, the texture is
    /// premultiplied as well, so convert it back to straight with `metaphorUnpremultiply()` before
    /// multiplying by the color.
    ///
    /// - Parameters:
    ///   - source: The MSL shader source.
    ///   - fragment: The name of the fragment shader function.
    /// - Returns: A ``Shader2D`` instance.
    /// - Throws: ``MetaphorError``. A compilation failure raises
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``, and a missing function raises
    ///   ``MetaphorError/material(_:)`` with ``MetaphorError/MaterialFailure/shaderNotFound(_:)``.
    public func createShader(source: String, fragment: String) throws -> Shader2D {
        try context.createShader(source: source, fragment: fragment)
    }

    /// Loads a custom 2D fragment shader from an external MSL file.
    ///
    /// ```swift
    /// let wave = try loadShader("data/wave.metal", fragment: "waveFragment")
    ///
    /// func draw() {
    ///     shader(wave)
    ///     rect(0, 0, width, height)   // the shape becomes the surface the shader runs on
    ///     resetShader()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: The path to the MSL source file.
    ///   - fragment: The name of the fragment shader function.
    /// - Returns: A ``Shader2D`` instance.
    /// - Throws: ``MetaphorError``. A load failure raises
    ///   ``MetaphorError/shaderSourceLoadFailed(path:detail:)``, a compilation failure raises
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``, and a missing function raises
    ///   ``MetaphorError/material(_:)`` with ``MetaphorError/MaterialFailure/shaderNotFound(_:)``.
    public func loadShader(_ path: String, fragment: String) throws -> Shader2D {
        try context.loadShader(path, fragment: fragment)
    }

    /// Applies a custom fragment shader to subsequent 2D drawing.
    /// - Parameter shader: The shader to apply.
    public func shader(_ shader: Shader2D) {
        context.shader(shader)
    }

    /// Clears the custom 2D shader and restores the built-in shader.
    public func resetShader() {
        context.resetShader()
    }
}
