// MARK: - Pixel Manipulation

extension Sketch {

    /// Direct access to the canvas pixel data as packed UInt32 values.
    ///
    /// Each element is a BGRA-packed color: `(A << 24) | (R << 16) | (G << 8) | B`.
    /// Use `color()` to create packed values. Index with `pixels[y * Int(width) + x]`.
    ///
    /// Call ``loadPixels()`` before accessing and ``updatePixels()`` after writing.
    public var pixels: UnsafeMutableBufferPointer<UInt32> {
        guard let pb = context.pixelBuffer else {
            return UnsafeMutableBufferPointer(start: nil, count: 0)
        }
        return pb.pixels
    }

    /// Prepare the pixel buffer for direct pixel manipulation.
    ///
    /// Creates the buffer on first call. Subsequent calls reuse the existing buffer.
    /// After calling this, write to ``pixels`` and then call ``updatePixels()``.
    public func loadPixels() {
        context.loadPixels()
    }

    /// Upload modified pixel data and draw it to the canvas.
    ///
    /// Transfers the pixel buffer to the GPU texture and renders it as a
    /// full-screen quad. Call this after writing to ``pixels``.
    public func updatePixels() {
        context.updatePixels()
    }
}
