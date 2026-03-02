import Metal
import simd

/// Provide an offscreen 2D drawing buffer (equivalent to Processing's `createGraphics()`).
///
/// Owns an independent Canvas2D and can draw separately from the main canvas.
/// The result can be extracted as an MImage and rendered onto the main canvas with `image()`.
///
/// ```swift
/// let pg = createGraphics(400, 400)
/// pg.beginDraw()
/// pg.background(.black)
/// pg.fill(.red)
/// pg.circle(200, 200, 100)
/// pg.endDraw()
/// image(pg, 0, 0)
/// ```
@MainActor
public final class Graphics {
    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureManager: TextureManager
    private let canvas: Canvas2D
    private var commandBuffer: MTLCommandBuffer?
    private var encoder: MTLRenderCommandEncoder?

    /// Return the width in pixels.
    public var width: Float { canvas.width }

    /// Return the height in pixels.
    public var height: Float { canvas.height }

    /// Return the internal color texture for MImage extraction.
    public var texture: MTLTexture { textureManager.colorTexture }

    // MARK: - Initialization

    init(device: MTLDevice, shaderLibrary: ShaderLibrary, depthStencilCache: DepthStencilCache, width: Int, height: Int) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        self.textureManager = try TextureManager(device: device, width: width, height: height, sampleCount: 1)
        self.canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLibrary,
            depthStencilCache: depthStencilCache,
            width: Float(width),
            height: Float(height),
            sampleCount: 1
        )
    }

    // MARK: - Draw Lifecycle

    /// Begin drawing by creating a command buffer and render command encoder.
    public func beginDraw() {
        guard let cb = commandQueue.makeCommandBuffer() else { return }
        self.commandBuffer = cb

        guard let enc = cb.makeRenderCommandEncoder(descriptor: textureManager.renderPassDescriptor) else {
            cb.commit()
            self.commandBuffer = nil
            return
        }
        self.encoder = enc
        canvas.begin(encoder: enc)
    }

    /// End drawing by flushing, committing, and waiting for GPU completion.
    public func endDraw() {
        canvas.end()
        encoder?.endEncoding()
        encoder = nil
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// Return the offscreen texture as an MImage.
    /// - Returns: An MImage wrapping the internal color texture.
    public func toImage() -> MImage {
        MImage(texture: textureManager.colorTexture)
    }

    // MARK: - Drawing Methods (forwarded to Canvas2D)

    /// Set the background color.
    /// - Parameter color: The background color.
    public func background(_ color: Color) { canvas.background(color) }

    /// Set the background to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func background(_ gray: Float) { canvas.background(gray) }

    /// Set the background color using channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: Optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.background(v1, v2, v3, a) }

    /// Set the fill color.
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) { canvas.fill(color) }

    /// Set the fill color using channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: Optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.fill(v1, v2, v3, a) }

    /// Set the fill to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func fill(_ gray: Float) { canvas.fill(gray) }

    /// Set the fill to a grayscale value with alpha.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) { canvas.fill(gray, alpha) }

    /// Disable filling shapes.
    public func noFill() { canvas.noFill() }

    /// Set the stroke color.
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) { canvas.stroke(color) }

    /// Set the stroke color using channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: Optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.stroke(v1, v2, v3, a) }

    /// Set the stroke to a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func stroke(_ gray: Float) { canvas.stroke(gray) }

    /// Set the stroke to a grayscale value with alpha.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) { canvas.stroke(gray, alpha) }

    /// Disable stroking shapes.
    public func noStroke() { canvas.noStroke() }

    /// Set the stroke weight.
    /// - Parameter weight: The stroke width in pixels.
    public func strokeWeight(_ weight: Float) { canvas.strokeWeight(weight) }

    /// Set the stroke cap style.
    /// - Parameter cap: The cap style.
    public func strokeCap(_ cap: StrokeCap) { canvas.strokeCap(cap) }

    /// Set the stroke join style.
    /// - Parameter join: The join style.
    public func strokeJoin(_ join: StrokeJoin) { canvas.strokeJoin(join) }

    /// Set the blend mode for subsequent drawing operations.
    /// - Parameter mode: The blend mode.
    public func blendMode(_ mode: BlendMode) { canvas.blendMode(mode) }

    /// Set the color mode and optional maximum channel values.
    /// - Parameters:
    ///   - space: The color space (RGB or HSB).
    ///   - max1: Maximum value for the first channel.
    ///   - max2: Maximum value for the second channel.
    ///   - max3: Maximum value for the third channel.
    ///   - maxA: Maximum value for the alpha channel.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) { canvas.colorMode(space, max1, max2, max3, maxA) }

    /// Set the color mode with a uniform maximum for all channels.
    /// - Parameters:
    ///   - space: The color space.
    ///   - maxAll: Maximum value applied to all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas.colorMode(space, maxAll) }

    /// Set the rectangle drawing mode.
    /// - Parameter mode: The rect mode.
    public func rectMode(_ mode: RectMode) { canvas.rectMode(mode) }

    /// Set the ellipse drawing mode.
    /// - Parameter mode: The ellipse mode.
    public func ellipseMode(_ mode: EllipseMode) { canvas.ellipseMode(mode) }

    /// Set the image drawing mode.
    /// - Parameter mode: The image mode.
    public func imageMode(_ mode: ImageMode) { canvas.imageMode(mode) }

    /// Set the tint color for images.
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) { canvas.tint(color) }

    /// Set the tint color using channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: Optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.tint(v1, v2, v3, a) }

    /// Disable image tinting.
    public func noTint() { canvas.noTint() }

    /// Push the current drawing state (style and transform) onto the stack.
    public func push() { canvas.push() }

    /// Pop the most recent drawing state (style and transform) from the stack.
    public func pop() { canvas.pop() }

    /// Translate the coordinate system by the given offset.
    /// - Parameters:
    ///   - x: Horizontal offset.
    ///   - y: Vertical offset.
    public func translate(_ x: Float, _ y: Float) { canvas.translate(x, y) }

    /// Rotate the coordinate system by the given angle in radians.
    /// - Parameter angle: Rotation angle in radians.
    public func rotate(_ angle: Float) { canvas.rotate(angle) }

    /// Scale the coordinate system by the given factors.
    /// - Parameters:
    ///   - sx: Horizontal scale factor.
    ///   - sy: Vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) { canvas.scale(sx, sy) }

    /// Scale the coordinate system uniformly.
    /// - Parameter s: Uniform scale factor.
    public func scale(_ s: Float) { canvas.scale(s) }

    /// Draw a rectangle.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    ///   - w: Width.
    ///   - h: Height.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.rect(x, y, w, h) }

    /// Draw a square.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    ///   - size: Side length.
    public func square(_ x: Float, _ y: Float, _ size: Float) { canvas.square(x, y, size) }

    /// Draw an ellipse.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    ///   - w: Width.
    ///   - h: Height.
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.ellipse(x, y, w, h) }

    /// Draw a circle.
    /// - Parameters:
    ///   - x: Center X coordinate.
    ///   - y: Center Y coordinate.
    ///   - diameter: Diameter of the circle.
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) { canvas.circle(x, y, diameter) }

    /// Draw a line between two points.
    /// - Parameters:
    ///   - x1: Start X.
    ///   - y1: Start Y.
    ///   - x2: End X.
    ///   - y2: End Y.
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) { canvas.line(x1, y1, x2, y2) }

    /// Draw a triangle.
    /// - Parameters:
    ///   - x1: First vertex X.
    ///   - y1: First vertex Y.
    ///   - x2: Second vertex X.
    ///   - y2: Second vertex Y.
    ///   - x3: Third vertex X.
    ///   - y3: Third vertex Y.
    public func triangle(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) { canvas.triangle(x1, y1, x2, y2, x3, y3) }

    /// Draw a quadrilateral.
    /// - Parameters:
    ///   - x1: First vertex X.
    ///   - y1: First vertex Y.
    ///   - x2: Second vertex X.
    ///   - y2: Second vertex Y.
    ///   - x3: Third vertex X.
    ///   - y3: Third vertex Y.
    ///   - x4: Fourth vertex X.
    ///   - y4: Fourth vertex Y.
    public func quad(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float, _ y4: Float) { canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4) }

    /// Draw a single point.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    public func point(_ x: Float, _ y: Float) { canvas.point(x, y) }

    /// Draw an arc.
    /// - Parameters:
    ///   - x: Center X coordinate.
    ///   - y: Center Y coordinate.
    ///   - w: Width.
    ///   - h: Height.
    ///   - startAngle: Start angle in radians.
    ///   - stopAngle: Stop angle in radians.
    ///   - mode: Arc drawing mode.
    public func arc(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ startAngle: Float, _ stopAngle: Float, _ mode: ArcMode = .open) { canvas.arc(x, y, w, h, startAngle, stopAngle, mode) }

    /// Draw a polygon from an array of points.
    /// - Parameter points: Array of (x, y) tuples defining the polygon vertices.
    public func polygon(_ points: [(Float, Float)]) { canvas.polygon(points) }

    /// Draw a cubic Bezier curve.
    /// - Parameters:
    ///   - x1: Start point X.
    ///   - y1: Start point Y.
    ///   - cx1: First control point X.
    ///   - cy1: First control point Y.
    ///   - cx2: Second control point X.
    ///   - cy2: Second control point Y.
    ///   - x2: End point X.
    ///   - y2: End point Y.
    public func bezier(_ x1: Float, _ y1: Float, _ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x2: Float, _ y2: Float) { canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2) }

    /// Draw a Catmull-Rom spline curve.
    /// - Parameters:
    ///   - x1: First control point X.
    ///   - y1: First control point Y.
    ///   - x2: Start point X.
    ///   - y2: Start point Y.
    ///   - x3: End point X.
    ///   - y3: End point Y.
    ///   - x4: Second control point X.
    ///   - y4: Second control point Y.
    public func curve(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float, _ y4: Float) { canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4) }

    /// Begin recording vertices for a custom shape.
    /// - Parameter mode: The shape mode (polygon, triangles, etc.).
    public func beginShape(_ mode: ShapeMode = .polygon) { canvas.beginShape(mode) }

    /// Add a vertex to the current shape being recorded.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    public func vertex(_ x: Float, _ y: Float) { canvas.vertex(x, y) }

    /// Add a cubic Bezier vertex to the current shape.
    /// - Parameters:
    ///   - cx1: First control point X.
    ///   - cy1: First control point Y.
    ///   - cx2: Second control point X.
    ///   - cy2: Second control point Y.
    ///   - x: End point X.
    ///   - y: End point Y.
    public func bezierVertex(_ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x: Float, _ y: Float) { canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y) }

    /// Add a Catmull-Rom spline vertex to the current shape.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    public func curveVertex(_ x: Float, _ y: Float) { canvas.curveVertex(x, y) }

    /// End recording and draw the current shape.
    /// - Parameter close: Whether to close the shape.
    public func endShape(_ close: CloseMode = .open) { canvas.endShape(close) }

    /// Draw an image at its original size.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    public func image(_ img: MImage, _ x: Float, _ y: Float) { canvas.image(img, x, y) }

    /// Draw an image at a specified size.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    ///   - w: Width.
    ///   - h: Height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.image(img, x, y, w, h) }

    /// Set the text size.
    /// - Parameter size: Font size in points.
    public func textSize(_ size: Float) { canvas.textSize(size) }

    /// Set the font family.
    /// - Parameter family: Font family name.
    public func textFont(_ family: String) { canvas.textFont(family) }

    /// Set the text alignment.
    /// - Parameters:
    ///   - horizontal: Horizontal alignment.
    ///   - vertical: Vertical alignment.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) { canvas.textAlign(horizontal, vertical) }

    /// Draw a text string at the specified position.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) { canvas.text(string, x, y) }

    /// Return the rendered width of a text string.
    /// - Parameter string: The text to measure.
    /// - Returns: The width in pixels.
    public func textWidth(_ string: String) -> Float { canvas.textWidth(string) }

    /// Return the ascent of the current font.
    /// - Returns: The font ascent in pixels.
    public func textAscent() -> Float { canvas.textAscent() }

    /// Return the descent of the current font.
    /// - Returns: The font descent in pixels.
    public func textDescent() -> Float { canvas.textDescent() }
}
