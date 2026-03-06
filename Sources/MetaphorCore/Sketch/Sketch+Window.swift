#if os(macOS)

extension Sketch {
    /// Create a secondary window for multi-window output.
    ///
    /// Each window has its own canvas, renderer, and input handling.
    /// Draw to it using the ``SketchWindow/draw(_:)`` method with a closure.
    ///
    /// ```swift
    /// var preview: SketchWindow?
    ///
    /// func setup() {
    ///     preview = createWindow(SketchWindowConfig(
    ///         width: 400, height: 300, title: "Preview"
    ///     ))
    /// }
    ///
    /// func draw() {
    ///     background(.black)
    ///     fill(.white)
    ///     circle(width / 2, height / 2, 200)
    ///
    ///     preview?.draw { ctx in
    ///         ctx.background(0.2)
    ///         ctx.fill(.red)
    ///         ctx.circle(200, 150, 100)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter config: The window configuration.
    /// - Returns: A new ``SketchWindow``, or `nil` if creation fails.
    public func createWindow(_ config: SketchWindowConfig = SketchWindowConfig()) -> SketchWindow? {
        context.createWindow(config)
    }

    /// Close all secondary windows created from this sketch.
    public func closeAllWindows() {
        context.closeAllWindows()
    }
}

#endif
