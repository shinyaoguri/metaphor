extension SketchContext {

    // MARK: - Shape Mode Settings

    /// Sets the coordinate interpretation mode for rectangles.
    /// - Parameter mode: The rectangle drawing mode.
    public func rectMode(_ mode: RectMode) {
        canvas.rectMode(mode)
    }

    /// Sets the coordinate interpretation mode for ellipses.
    /// - Parameter mode: The ellipse drawing mode.
    public func ellipseMode(_ mode: EllipseMode) {
        canvas.ellipseMode(mode)
    }

    /// Sets the coordinate interpretation mode for images.
    /// - Parameter mode: The image drawing mode.
    public func imageMode(_ mode: ImageMode) {
        canvas.imageMode(mode)
    }

    // MARK: - Drawing Style

    /// Returns the current shared drawing style.
    public var drawingStyle: DrawingStyle {
        get {
            DrawingStyle(
                fillColor: canvas.fillColor,
                strokeColor: canvas.strokeColor,
                hasFill: canvas.hasFill,
                hasStroke: canvas.hasStroke,
                colorModeConfig: canvas.colorModeConfig
            )
        }
        set {
            canvas.syncStyle(newValue)
            canvas3D.syncStyle(newValue)
        }
    }

    // MARK: - Color Mode

    /// Sets the color space and maximum channel values for both 2D and 3D canvases.
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - max1: The maximum value for the first channel.
    ///   - max2: The maximum value for the second channel.
    ///   - max3: The maximum value for the third channel.
    ///   - maxA: The maximum value for the alpha channel.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        canvas.colorMode(space, max1, max2, max3, maxA)
        canvas3D.colorMode(space, max1, max2, max3, maxA)
    }

    /// Sets the color space with a uniform maximum value for both 2D and 3D canvases.
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The uniform maximum value for all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        canvas.colorMode(space, maxAll)
        canvas3D.colorMode(space, maxAll)
    }

    // MARK: - Background

    /// Fills the background with the specified color.
    /// - Parameter color: The background color.
    public func background(_ color: Color) {
        canvas.background(color)
    }

    /// Fills the background with a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func background(_ gray: Float) {
        canvas.background(gray)
    }

    /// Fills the background with color components interpreted according to the current color mode.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.background(v1, v2, v3, a)
    }

    // MARK: - Style (2D + 3D shared)

    /// Sets the fill color for both 2D and 3D canvases.
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) {
        canvas.fill(color)
        canvas3D.fill(color)
    }

    /// Sets the fill color interpreted according to the current color mode for both 2D and 3D canvases.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.fill(v1, v2, v3, a)
        canvas3D.fill(v1, v2, v3, a)
    }

    /// Sets the fill color using a grayscale value for both 2D and 3D canvases.
    /// - Parameter gray: The grayscale intensity.
    public func fill(_ gray: Float) {
        canvas.fill(gray)
        canvas3D.fill(gray)
    }

    /// Sets the fill color using a grayscale value with alpha for both 2D and 3D canvases.
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) {
        canvas.fill(gray, alpha)
        canvas3D.fill(gray, alpha)
    }

    /// Disables fill for both 2D and 3D canvases.
    public func noFill() {
        canvas.noFill()
        canvas3D.noFill()
    }

    /// Sets the stroke color for both 2D and 3D canvases.
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) {
        canvas.stroke(color)
        canvas3D.stroke(color)
    }

    /// Sets the stroke color interpreted according to the current color mode for both 2D and 3D canvases.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.stroke(v1, v2, v3, a)
        canvas3D.stroke(v1, v2, v3, a)
    }

    /// Sets the stroke color using a grayscale value for both 2D and 3D canvases.
    /// - Parameter gray: The grayscale intensity.
    public func stroke(_ gray: Float) {
        canvas.stroke(gray)
        canvas3D.stroke(gray)
    }

    /// Sets the stroke color using a grayscale value with alpha for both 2D and 3D canvases.
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        canvas.stroke(gray, alpha)
        canvas3D.stroke(gray, alpha)
    }

    /// Disables stroke for both 2D and 3D canvases.
    public func noStroke() {
        canvas.noStroke()
        canvas3D.noStroke()
    }

    /// Sets the stroke weight (2D only).
    /// - Parameter weight: The line thickness in pixels.
    public func strokeWeight(_ weight: Float) {
        canvas.strokeWeight(weight)
    }

    /// Sets the stroke cap style.
    /// - Parameter cap: The end-cap style for strokes.
    public func strokeCap(_ cap: StrokeCap) {
        canvas.strokeCap(cap)
    }

    /// Sets the stroke join style.
    /// - Parameter join: The join style for stroke corners.
    public func strokeJoin(_ join: StrokeJoin) {
        canvas.strokeJoin(join)
    }

    /// Sets the blend mode for rendering.
    /// - Parameter mode: The blend mode to apply.
    public func blendMode(_ mode: BlendMode) {
        canvas.blendMode(mode)
    }

    // MARK: - Tint

    /// Sets the tint color for images.
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) {
        canvas.tint(color)
    }

    /// Sets the tint color interpreted according to the current color mode.
    /// - Parameters:
    ///   - v1: The first color component.
    ///   - v2: The second color component.
    ///   - v3: The third color component.
    ///   - a: The optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.tint(v1, v2, v3, a)
    }

    /// Sets the tint color using a grayscale value.
    /// - Parameter gray: The grayscale intensity.
    public func tint(_ gray: Float) {
        canvas.tint(gray)
    }

    /// Sets the tint color using a grayscale value with alpha.
    /// - Parameters:
    ///   - gray: The grayscale intensity.
    ///   - alpha: The alpha value.
    public func tint(_ gray: Float, _ alpha: Float) {
        canvas.tint(gray, alpha)
    }

    /// Disables the image tint.
    public func noTint() {
        canvas.noTint()
    }
}
