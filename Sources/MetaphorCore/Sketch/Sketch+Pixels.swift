// MARK: - Pixel Manipulation

extension Sketch {

    /// Direct access to the canvas pixel data, as packed `UInt32` values.
    ///
    /// Each element is a BGRA packed color: `(A << 24) | (R << 16) | (G << 8) | B`.
    /// Use `color()` to build a packed value. Index into it as `pixels[y * Int(width) + x]`.
    ///
    /// Call ``loadPixels()`` before reading and ``updatePixels()`` after writing.
    ///
    /// Colors are **straight alpha** (the same values `fill()` and `color()` use, before the alpha
    /// multiplication). Reading a semi-transparent pixel does not darken its color, and writing
    /// back what you read leaves the image unchanged (ADR-0012 / #848).
    ///
    /// - Note: Because this is a read accessor it **never crashes** (ADR-0005 / #356).
    ///   It returns an empty buffer before ``loadPixels()``, before SketchRunner has prepared the
    ///   context (in `init` or a property initializer), and after teardown. That is why, unlike the
    ///   drawing APIs, it does not go through ``Sketch/context``.
    public var pixels: UnsafeMutableBufferPointer<UInt32> {
        guard let pb = _context?.pixelBuffer else {
            return UnsafeMutableBufferPointer(start: nil, count: 0)
        }
        return pb.pixels
    }

    /// Reads the canvas contents **as of the moment of the call** back into the ``pixels`` array
    /// (Processing compatible).
    ///
    /// After the call, read and write ``pixels`` and then apply the result with ``updatePixels()``.
    /// Calling it partway through `draw()` reads the state with everything issued so far applied
    /// (`background()`, shapes, `image()`).
    ///
    /// ```swift
    /// func draw() {
    ///     background(0)
    ///     fill(255, 0, 0)
    ///     circle(width / 2, height / 2, 100)
    ///     loadPixels()                 // everything drawn so far (up to the circle) is readable
    ///     for i in 0..<pixels.count { pixels[i] ^= 0x00FF_FFFF }  // invert the colors
    ///     updatePixels()
    /// }
    /// ```
    ///
    /// - Important: Reading back the same frame works on the **normal path with shadows off**. With
    ///   shadows enabled (`enableShadows()`), `draw()` runs first as a recording pass and cannot be
    ///   split, so what you read is **the contents of the most recently committed frame** (warned
    ///   once). The same applies when it is called outside `draw()` (in `setup()` or between
    ///   frames).
    ///
    /// - Note: It blocks the main thread to wait for the GPU to finish (the same as Processing).
    ///   Sketches that never call `loadPixels()` pay no cost at all.
    ///
    /// - Note: Because it waits, it is currently also **the only public API that makes this
    ///   frame's ``Sketch/compute()`` results readable from the CPU**: the command buffer it
    ///   commits is the same one that carried the frame's dispatches, so a ``GPUBuffer`` read
    ///   after it returns sees what the kernels wrote. That holds only on the same-frame path
    ///   above — with shadows on, or outside `draw()`, it waits on a separate command buffer
    ///   and this frame's compute is still in flight. A read back that does not go through the
    ///   pixel path is tracked in Issue #1136.
    ///
    /// - Note: Because the read back splits the render pass internally, 3D geometry drawn on
    ///   opposite sides of a `loadPixels()` is not depth compared (depth is cleared in the
    ///   continuation pass).
    ///
    /// - Note: `loadPixels()` is also a flush point for the 2D batch. On the immediate path with
    ///   shadows off, stacking order is decided by **encode order** rather than call order, so 2D
    ///   drawn **before** `loadPixels()` ends up behind 3D drawn **after** it. Draw the 2D you want
    ///   in front of the 3D after `loadPixels()` (#832; the full list of triggers is in the
    ///   2026-08-16 addendum to
    ///   [ADR-0003](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0003-unified-command-stream.md)).
    ///   Within each side of a `loadPixels()`, 2D still appears in front of 3D just as it does at
    ///   the end of a frame.
    public func loadPixels() {
        context.loadPixels()
    }

    /// Uploads the modified pixel data and draws it to the canvas.
    ///
    /// Transfers the pixel buffer to a GPU texture and renders it as a fullscreen quad. Call this
    /// after writing to ``pixels``.
    ///
    /// - Note: Does nothing if ``loadPixels()`` has never been called.
    public func updatePixels() {
        context.updatePixels()
    }

    /// Reads the color of a single pixel (compatible with Processing's `get(x, y)`).
    ///
    /// It is an entry point that saves you from unpacking the ``pixels`` values by hand; it reads
    /// the very same buffer.
    ///
    /// ```swift
    /// func draw() {
    ///     background(0)
    ///     fill(255, 0, 0)
    ///     circle(width / 2, height / 2, 100)
    ///     loadPixels()                                  // ← read back first
    ///     let c = get(Int(width) / 2, Int(height) / 2)  // the red at the center of the circle
    ///     print(c)
    /// }
    /// ```
    ///
    /// - Important: **It does not read back implicitly.** Call ``loadPixels()`` first (without it,
    ///   the call returns black and warns once). Processing's `get()` is merely slow, but a read
    ///   back in metaphor also **splits the render pass** on top of waiting for the GPU, and
    ///   through the depth clear and the 2D/3D stacking order that **changes the image itself**
    ///   (see the Notes on ``loadPixels()``). To keep that from happening on every single pixel
    ///   read, the read back is confined to an explicit ``loadPixels()``.
    ///
    /// - Important: With shadows enabled (`enableShadows()`), ``loadPixels()`` cannot read back the
    ///   same frame and instead reads **the contents of the most recently committed frame**.
    ///   `get()` reads that result, so it carries the same restriction.
    ///
    /// - Parameters:
    ///   - x: The horizontal pixel coordinate.
    ///   - y: The vertical pixel coordinate.
    /// - Returns: A straight alpha ``Color`` (the same value you pass to `fill()`; ADR-0012).
    ///   Returns black when out of range or when ``loadPixels()`` has not been called.
    ///
    /// - Note: Because this is a read accessor it **never crashes** (ADR-0005 / #356).
    ///   It returns black even before the context is prepared (in `init` or a property
    ///   initializer).
    public func get(_ x: Int, _ y: Int) -> Color {
        guard let ctx = _context else { return .black }
        return ctx.get(x, y)
    }

    /// Extracts a rectangular region of the canvas as an ``MImage`` (compatible with Processing's
    /// `get(x, y, w, h)`).
    ///
    /// The returned image is **exactly the requested `w` × `h`**. Any part that falls outside the
    /// canvas is filled with transparency (alpha = 0), just as in Processing. It can be drawn
    /// directly with `image()`.
    ///
    /// ```swift
    /// loadPixels()
    /// if let stamp = get(0, 0, 64, 64) {
    ///     image(stamp, 100, 100)
    /// }
    /// ```
    ///
    /// - Important: Just like ``get(_:_:)``, **it does not read back implicitly**. The restriction
    ///   with shadows on is the same as well (see the `- Important:` on ``loadPixels()``).
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the top-left corner of the region to extract.
    ///   - y: The y coordinate of the top-left corner of the region to extract.
    ///   - w: The width to extract (1 or greater).
    ///   - h: The height to extract (1 or greater).
    /// - Returns: The extracted ``MImage``. Returns nil when ``loadPixels()`` has not been called,
    ///   when the size is 0 or less, or when the texture allocation fails.
    public func get(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> MImage? {
        guard let ctx = _context else { return nil }
        return ctx.get(x, y, w, h)
    }

    /// Writes the color of a single pixel (compatible with Processing's `set(x, y, c)`).
    ///
    /// ```swift
    /// loadPixels()
    /// set(10, 20, Color(r: 1, g: 0, b: 0))
    /// updatePixels()               // ← this is what puts it on the canvas
    /// ```
    ///
    /// - Important: The write goes to the CPU-side ``pixels`` buffer. Putting it on the canvas
    ///   requires ``updatePixels()``, unlike Processing's `set()`, which takes effect immediately.
    ///   It does nothing if ``loadPixels()`` has not been called (warned once).
    ///
    /// - Parameters:
    ///   - x: The horizontal pixel coordinate. Out-of-range values are ignored.
    ///   - y: The vertical pixel coordinate. Out-of-range values are ignored.
    ///   - color: The color to write. It is packed as straight alpha (ADR-0012).
    public func set(_ x: Int, _ y: Int, _ color: Color) {
        context.set(x, y, color)
    }
}
