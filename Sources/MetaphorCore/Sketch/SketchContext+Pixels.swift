import Metal

// MARK: - Canvas-Level Pixel Access

extension SketchContext {

    /// The pixel buffer for direct pixel manipulation, lazily created.
    private static var _pixelBufferKey: UInt8 = 0

    /// Access the pixel buffer, creating it if needed.
    var pixelBuffer: PixelBuffer? {
        get {
            objc_getAssociatedObject(self, &Self._pixelBufferKey) as? PixelBuffer
        }
        set {
            objc_setAssociatedObject(self, &Self._pixelBufferKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Ensure the pixel buffer exists and matches the canvas dimensions.
    ///
    /// Creates a new pixel buffer on first call or when the canvas size changes.
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)

        if let existing = pixelBuffer, existing.width == w, existing.height == h {
            return
        }

        pixelBuffer = PixelBuffer(width: w, height: h, device: renderer.device)
    }

    /// Upload the pixel buffer to the GPU and draw it as a full-screen quad.
    ///
    /// Call this after modifying the `pixels` buffer to display the changes.
    public func updatePixels() {
        guard let pb = pixelBuffer else { return }
        pb.upload()
        canvas.drawTexturedQuad(texture: pb.texture, x: 0, y: 0, w: width, h: height)
    }
}
