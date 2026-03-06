// MARK: - Style (Shape Modes, Color, Fill, Stroke, Blend, Tint)

extension Sketch {

    // MARK: Shape Mode Settings

    /// Set the rectangle drawing mode.
    ///
    /// - Parameter mode: The rectangle interpretation mode.
    public func rectMode(_ mode: RectMode) {
        context.rectMode(mode)
    }

    /// Set the ellipse drawing mode.
    ///
    /// - Parameter mode: The ellipse interpretation mode.
    public func ellipseMode(_ mode: EllipseMode) {
        context.ellipseMode(mode)
    }

    /// Set the image drawing mode.
    ///
    /// - Parameter mode: The image interpretation mode.
    public func imageMode(_ mode: ImageMode) {
        context.imageMode(mode)
    }

    // MARK: Color Mode

    /// Set the color mode with per-channel maximums.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - max1: The maximum value for the first channel.
    ///   - max2: The maximum value for the second channel.
    ///   - max3: The maximum value for the third channel.
    ///   - maxA: The maximum value for the alpha channel.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        context.colorMode(space, max1, max2, max3, maxA)
    }

    /// Set the color mode with a single maximum for all channels.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The maximum value for all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        context.colorMode(space, maxAll)
    }

    // MARK: Background

    /// Clear the canvas with the specified color.
    ///
    /// - Parameter color: The background color.
    public func background(_ color: Color) {
        context.background(color)
    }

    /// Clear the canvas with a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness (0 = black, 1 = white).
    public func background(_ gray: Float) {
        context.background(gray)
    }

    /// Clear the canvas with the specified color channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.background(v1, v2, v3, a)
    }

    // MARK: Style

    /// Set the fill color.
    ///
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) {
        context.fill(color)
    }

    /// Set the fill color using channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.fill(v1, v2, v3, a)
    }

    /// Set the fill color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func fill(_ gray: Float) {
        context.fill(gray)
    }

    /// Set the fill color using a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func fill(_ gray: Float, _ alpha: Float) {
        context.fill(gray, alpha)
    }

    /// Disable filling shapes.
    public func noFill() {
        context.noFill()
    }

    /// Set the stroke color.
    ///
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) {
        context.stroke(color)
    }

    /// Set the stroke color using channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.stroke(v1, v2, v3, a)
    }

    /// Set the stroke color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func stroke(_ gray: Float) {
        context.stroke(gray)
    }

    /// Set the stroke color using a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        context.stroke(gray, alpha)
    }

    /// Disable stroking shapes.
    public func noStroke() {
        context.noStroke()
    }

    /// Set the stroke weight (line thickness).
    ///
    /// - Parameter weight: The stroke width in pixels.
    public func strokeWeight(_ weight: Float) {
        context.strokeWeight(weight)
    }

    /// Set the stroke cap style.
    ///
    /// - Parameter cap: The line cap style.
    public func strokeCap(_ cap: StrokeCap) {
        context.strokeCap(cap)
    }

    /// Set the stroke join style.
    ///
    /// - Parameter join: The line join style.
    public func strokeJoin(_ join: StrokeJoin) {
        context.strokeJoin(join)
    }

    /// Set the blend mode for subsequent drawing operations.
    ///
    /// - Parameter mode: The blend mode to apply.
    public func blendMode(_ mode: BlendMode) {
        context.blendMode(mode)
    }

    // MARK: Tint

    /// Set the image tint color.
    ///
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) {
        context.tint(color)
    }

    /// Set the image tint color using channel values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value (red or hue).
    ///   - v2: The second color channel value (green or saturation).
    ///   - v3: The third color channel value (blue or brightness).
    ///   - a: The optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        context.tint(v1, v2, v3, a)
    }

    /// Set the image tint using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness.
    public func tint(_ gray: Float) {
        context.tint(gray)
    }

    /// Set the image tint using a grayscale value with alpha.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness.
    ///   - alpha: The alpha (opacity) value.
    public func tint(_ gray: Float, _ alpha: Float) {
        context.tint(gray, alpha)
    }

    /// Remove the image tint.
    public func noTint() {
        context.noTint()
    }
}
