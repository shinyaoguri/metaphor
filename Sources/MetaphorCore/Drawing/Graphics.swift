import Metal
import simd

/// Provides an offscreen 2D drawing buffer (the equivalent of Processing's
/// `createGraphics()`).
///
/// It owns an independent Canvas2D, so it draws separately from the main canvas.
/// The result is obtained as an MImage and can be drawn to the main canvas with `image()`.
///
/// The buffer **starts out transparent** (alpha 0), so it can be layered over the main canvas
/// or placed in the foreground of a `MergePass(.alpha)` without covering what is underneath.
/// Call ``background(_:)-(Color)`` for an opaque backdrop (#914).
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

    // メインレンダラーと同じトリプルバッファリング。
    // Canvas2D の頂点バッファは 3 スロット持つが、以前は常にスロット 0 を
    // 使っていたため、毎フレーム描画すると GPU がまだ前フレームを読んでいる
    // 共有バッファを CPU が上書きし、ちらつき・破損の原因になっていた。
    private static let inflightCount = 3
    private let inflightSemaphore = DispatchSemaphore(value: inflightCount)
    private var bufferIndex = 0

    /// For testing: the buffer slot that the next beginDraw uses.
    var nextBufferIndexForTesting: Int { bufferIndex }

    /// Copy-on-write rotation of the render target texture (#745).
    private let targetRotator: OffscreenTargetRotator

    /// The width in pixels.
    public var width: Float { canvas.width }

    /// The height in pixels.
    public var height: Float { canvas.height }

    /// The internal color texture, for obtaining an MImage.
    ///
    /// The contents of the returned texture are frozen at the next ``beginDraw()``
    /// (drawing rotates to a different texture, so an image already placed with
    /// `image()` is never rewritten afterwards. #745).
    public var texture: MTLTexture {
        targetRotator.markHandedOut()
        return textureManager.colorTexture
    }

    // MARK: - Initialization

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Int,
        height: Int
    ) throws {
        self.device = device
        // renderer の commandQueue を共有することで、メインキャンバスから
        // pg.texture を読む際に Metal の同一キュー内 commit-order 保証で
        // 自動的に順序付けされ、明示的な GPU 待機が不要になる。
        self.commandQueue = commandQueue
        // オフスクリーンは「層」として使うのが主用途なので、下地は透明で始める（#914）。
        // 不透明な黒で始めると image() や MergePass(.alpha) の前景に置いたときに
        // 下のものを覆ってしまう。従来の黒い下地が要るときは background(0) を呼ぶ。
        self.textureManager = try TextureManager(
            device: device, width: width, height: height,
            clearColor: .clear, sampleCount: 1)
        self.canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLibrary,
            depthStencilCache: depthStencilCache,
            width: Float(width),
            height: Float(height),
            sampleCount: 1
        )
        self.targetRotator = OffscreenTargetRotator(textureManager: textureManager)
        // Canvas2D は「いまレンダーパスに載っているクリア色」を覚えていて、それと同じ色の
        // background() はクリアに任せてクワッドを省く（Canvas2D+Background）。既定値は
        // メインキャンバス向けの不透明な黒なので、オフスクリーンの実際のクリア色（透明）へ
        // 揃えないと、初回パスの background(0) が「同じ色だから省略」と誤判定されて
        // 透明のまま残る（#914）。
        self.canvas.appliedClearColor = SIMD4<Float>(0, 0, 0, 0)
        self.canvas.onSetClearColor = { [weak textureManager] r, g, b, a in
            textureManager?.setClearColor(TextureManager.premultipliedClearColor(r, g, b, a))
        }
    }

    // MARK: - Draw Lifecycle

    /// Begins drawing by creating a command buffer and a render command encoder.
    public func beginDraw() {
        // endDraw 漏れの不均衡呼び出しでもセマフォが詰まらないよう先に閉じる
        if commandBuffer != nil { endDraw() }

        // 前のパスの絵を外へ渡していたら、描き先を別のテクスチャへ回す（#745）。
        // これで同一フレーム内に描き換えても、既に貼った絵は貼った時点のまま残る。
        targetRotator.rotateIfNeeded(commandQueue: commandQueue)

        // GPU が inflightCount フレーム以上遅れている場合はここでブロックし、
        // GPU がまだ読んでいる頂点バッファスロットへの上書きを防ぐ
        inflightSemaphore.wait()
        guard let cb = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }
        let semaphore = inflightSemaphore
        cb.addCompletedHandler { @Sendable _ in semaphore.signal() }
        self.commandBuffer = cb

        guard let enc = cb.makeRenderCommandEncoder(descriptor: textureManager.renderPassDescriptor)
        else {
            // commit して completed handler を発火させ、セマフォを返す
            cb.commit()
            self.commandBuffer = nil
            return
        }
        self.encoder = enc
        canvas.begin(encoder: enc, bufferIndex: bufferIndex)
        bufferIndex = (bufferIndex + 1) % Self.inflightCount
    }

    /// Ends drawing.
    ///
    /// `Graphics` shares the same `MTLCommandQueue` as the renderer, so commit order
    /// automatically orders any subsequent read from the main canvas correctly.
    /// By default it therefore returns immediately, without waiting for the GPU.
    ///
    /// - Parameter wait: When `true`, waits explicitly for GPU completion with
    ///   `waitUntilCompleted()`. This is needed only when reading the texture contents
    ///   directly on the CPU (with `getBytes`, for example).
    public func endDraw(wait: Bool = false) {
        canvas.end()
        encoder?.endEncoding()
        encoder = nil

        let shouldClearNext = canvas.backgroundCalledThisFrame
        textureManager.setShouldClear(shouldClearNext)
        canvas.frameWillClear = shouldClearNext
        if shouldClearNext {
            canvas.markPendingClearColorApplied()
        }

        commandBuffer?.commit()
        if wait {
            commandBuffer?.waitUntilCompleted()
        }
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// Returns the offscreen texture as an MImage.
    ///
    /// Drawing it with `image()` paints **the contents that were visible at that moment**.
    /// The same buffer can be redrawn and placed any number of times within a single frame
    /// (each redraw rotates the render target to a different texture, so the number of
    /// internal textures grows by the number of redraws. #745).
    ///
    /// ``MImage/loadPixels()`` on the returned `MImage` always reads the latest contents.
    ///
    /// - Returns: An MImage wrapping the internal color texture.
    public func toImage() -> MImage {
        let image = MImage(texture: textureManager.colorTexture)
        // リードバックを描画と同じキューに載せ、endDraw(wait: false) 直後の
        // loadPixels でも commit 順序で最新内容が読めるようにする
        image.preferredReadbackQueue = commandQueue
        targetRotator.markHandedOut(image)
        return image
    }

    // MARK: - Drawing Methods (forwarded to Canvas2D)

    /// Repaints the backdrop with a solid color.
    ///
    /// The backdrop of a fresh buffer is **transparent** (#914), so this is what makes it opaque.
    /// **The background replaces rather than composites** (ADR-0012 / #829): an alpha below 1 goes
    /// in as it is, and `background(0, 0, 0, 0)` returns the backdrop to transparent.
    ///
    /// - Parameter color: The background color (straight alpha).
    public func background(_ color: Color) { canvas.background(color) }

    /// Sets the background from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func background(_ gray: Float) { canvas.background(gray) }

    /// Sets the background color from channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.background(v1, v2, v3, a)
    }

    /// Sets the fill color.
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) { canvas.fill(color) }

    /// Sets the fill color from channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.fill(v1, v2, v3, a)
    }

    /// Sets the fill from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func fill(_ gray: Float) { canvas.fill(gray) }

    /// Sets the fill from a grayscale value and an alpha value.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func fill(_ gray: Float, _ alpha: Float) { canvas.fill(gray, alpha) }

    /// Disables filling of shapes.
    public func noFill() { canvas.noFill() }

    /// Sets the stroke color.
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) { canvas.stroke(color) }

    /// Sets the stroke color from channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.stroke(v1, v2, v3, a)
    }

    /// Sets the stroke from a grayscale value.
    /// - Parameter gray: The grayscale value.
    public func stroke(_ gray: Float) { canvas.stroke(gray) }

    /// Sets the stroke from a grayscale value and an alpha value.
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value.
    public func stroke(_ gray: Float, _ alpha: Float) { canvas.stroke(gray, alpha) }

    /// Disables stroking of shapes.
    public func noStroke() { canvas.noStroke() }

    /// Sets the stroke weight.
    /// - Parameter weight: The stroke weight in pixels.
    public func strokeWeight(_ weight: Float) { canvas.strokeWeight(weight) }

    /// Sets the stroke cap style.
    /// - Parameter cap: The cap style.
    public func strokeCap(_ cap: StrokeCap) { canvas.strokeCap(cap) }

    /// Sets the stroke join style.
    /// - Parameter join: The join style.
    public func strokeJoin(_ join: StrokeJoin) { canvas.strokeJoin(join) }

    /// Sets the blend mode for subsequent drawing operations.
    /// - Parameter mode: The blend mode.
    public func blendMode(_ mode: BlendMode) { canvas.blendMode(mode) }

    // MARK: - カスタムシェーダ（#647 / Epic #291 E2）

    /// Applies a custom 2D fragment shader to subsequent drawing.
    ///
    /// A shader created with `loadShader()` or `createShader()` can be shared with the
    /// main canvas (because it uses functions from the same ``ShaderLibrary``). The
    /// built-in `resolution` uniform is the size of this `Graphics`.
    /// - Parameter shader: The shader to apply.
    public func shader(_ shader: Shader2D) { canvas.shader(shader) }

    /// Clears the custom 2D shader and returns to the built-in shader.
    public func resetShader() { canvas.resetShader() }

    /// Wires up the hook that supplies the built-in time, mouse and frame count uniforms
    /// (called from `SketchContext.createGraphics`).
    func wireShaderInputs(_ provider: @escaping () -> Canvas2DShaderInputs) {
        canvas.shaderInputs = provider
        // 描画先テクスチャを使い回してよい時期の判定にフレーム番号を使う（#745）
        targetRotator.frameCountProvider = { provider().frameCount }
    }

    /// Sets the color mode and optional maximum channel values.
    /// - Parameters:
    ///   - space: The color space (RGB or HSB).
    ///   - max1: The maximum value of the first channel.
    ///   - max2: The maximum value of the second channel.
    ///   - max3: The maximum value of the third channel.
    ///   - maxA: The maximum value of the alpha channel.
    public func colorMode(
        _ space: ColorSpace, _ max1: Float? = nil, _ max2: Float? = nil, _ max3: Float? = nil,
        _ maxA: Float? = nil
    ) { canvas.colorMode(space, max1, max2, max3, maxA) }

    /// Sets the color mode with a uniform maximum value for all channels.
    /// - Parameters:
    ///   - space: The color space.
    ///   - maxAll: The maximum value applied to all channels.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas.colorMode(space, maxAll) }

    /// Sets the drawing mode for rectangles.
    /// - Parameter mode: The rectangle mode.
    public func rectMode(_ mode: RectMode) { canvas.rectMode(mode) }

    /// Sets the drawing mode for ellipses.
    /// - Parameter mode: The ellipse mode.
    public func ellipseMode(_ mode: EllipseMode) { canvas.ellipseMode(mode) }

    /// Sets the drawing mode for images.
    /// - Parameter mode: The image mode.
    public func imageMode(_ mode: ImageMode) { canvas.imageMode(mode) }

    /// Sets how a retained shape drawn with a position and a size reads its coordinates.
    /// - Parameter mode: The shape position mode.
    public func shapeMode(_ mode: ShapePositionMode) { canvas.shapeMode(mode) }

    /// Sets the tint color for images.
    /// - Parameter color: The tint color.
    public func tint(_ color: Color) { canvas.tint(color) }

    /// Sets the tint color from channel values.
    /// - Parameters:
    ///   - v1: The first color channel value.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: An optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.tint(v1, v2, v3, a)
    }

    /// Disables tinting of images.
    public func noTint() { canvas.noTint() }

    /// Pushes the current drawing state (style and transform) onto the stack.
    public func push() { canvas.push() }

    /// Pops the most recently saved drawing state (style and transform) off the stack.
    public func pop() { canvas.pop() }

    /// Pushes only the current transformation matrix onto the matrix stack.
    ///
    /// It does not push style, so it stacks independently of ``pushStyle()``.
    /// The stack is unwound on every ``beginDraw()`` (calling `endDraw()` while it is
    /// unbalanced does not carry it over to the next pass).
    public func pushMatrix() { canvas.pushMatrix() }

    /// Pops only the transformation matrix off the matrix stack. Style is unchanged.
    public func popMatrix() { canvas.popMatrix() }

    /// Pushes only the style state, excluding transforms, onto the style-only stack.
    ///
    /// The stack is unwound on every ``beginDraw()``.
    public func pushStyle() { canvas.pushStyle() }

    /// Pops only the style state off the style-only stack. Transforms are unchanged.
    public func popStyle() { canvas.popStyle() }

    /// Translates the coordinate system by the given offset.
    /// - Parameters:
    ///   - x: The horizontal offset.
    ///   - y: The vertical offset.
    public func translate(_ x: Float, _ y: Float) { canvas.translate(x, y) }

    /// Rotates the coordinate system by an angle in radians.
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: Float) { canvas.rotate(angle) }

    /// Scales the coordinate system by the given factors.
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) { canvas.scale(sx, sy) }

    /// Scales the coordinate system uniformly.
    /// - Parameter s: The uniform scale factor.
    public func scale(_ s: Float) { canvas.scale(s) }

    /// Multiplies the current transform by the given 3x3 matrix.
    /// - Parameter matrix: The 3x3 matrix to concatenate.
    public func applyMatrix(_ matrix: float3x3) { canvas.applyMatrix(matrix) }

    /// Multiplies the current transform by a Processing-style six-component affine matrix.
    ///
    /// The components are row-major, and the transform is `x' = n00*x + n01*y + n02` and
    /// `y' = n10*x + n11*y + n12`.
    public func applyMatrix(
        _ n00: Float, _ n01: Float, _ n02: Float,
        _ n10: Float, _ n11: Float, _ n12: Float
    ) { canvas.applyMatrix(n00, n01, n02, n10, n11, n12) }

    /// Resets the current transformation matrix to the identity matrix.
    public func resetMatrix() { canvas.resetMatrix() }

    /// Applies a shear along the x axis to the current transform.
    ///
    /// `x' = x + tan(angle) * y` (compatible with Processing's `shearX()`).
    /// - Parameter angle: The shear angle in radians.
    public func shearX(_ angle: Float) { canvas.shearX(angle) }

    /// Applies a shear along the y axis to the current transform.
    ///
    /// `y' = y + tan(angle) * x` (compatible with Processing's `shearY()`).
    /// - Parameter angle: The shear angle in radians.
    public func shearY(_ angle: Float) { canvas.shearY(angle) }

    /// Converts model coordinates to pixel coordinates **within this buffer** using the
    /// current transform.
    ///
    /// Where the API of the same name on `Sketch` returns pixel coordinates on the screen,
    /// `Graphics` returns coordinates inside the ``width`` × ``height`` offscreen buffer
    /// (the position at which `image()` places it is not included).
    ///
    /// - Parameters:
    ///   - x: The model x coordinate.
    ///   - y: The model y coordinate.
    /// - Returns: The pixel coordinates within the buffer.
    public func screenPosition(_ x: Float, _ y: Float) -> SIMD2<Float> {
        canvas.screenPosition(x, y)
    }

    /// Clips subsequent drawing to the given rectangle.
    ///
    /// The rectangle is in this buffer's pixel coordinates and is clamped to the
    /// ``width`` × ``height`` range. As on `Sketch`, it is **not affected by the current
    /// transform** (calling it inside ``translate(_:_:)`` does not move the rectangle).
    /// ``endClip()`` returns to the previous clip region, and clips can be nested.
    /// The clip state is unwound by ``endDraw(wait:)``, so forgetting to close one does
    /// not carry it over to the next pass.
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the clip region.
    ///   - y: The y coordinate of the clip region.
    ///   - w: The width of the clip region.
    ///   - h: The height of the clip region.
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.beginClip(x, y, w, h)
    }

    /// Ends the current clip region and restores the previous one.
    public func endClip() { canvas.endClip() }

    /// Draws a rectangle.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.rect(x, y, w, h) }

    /// Draws a square.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - size: The side length.
    public func square(_ x: Float, _ y: Float, _ size: Float) { canvas.square(x, y, size) }

    /// Draws an ellipse.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.ellipse(x, y, w, h)
    }

    /// Draws a circle.
    /// - Parameters:
    ///   - x: The x coordinate of the center.
    ///   - y: The y coordinate of the center.
    ///   - diameter: The diameter of the circle.
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) { canvas.circle(x, y, diameter) }

    /// Draws multiple circles in a single batch.
    /// - Parameter instances: The circle instances to draw.
    public func circles(_ instances: [CircleInstance]) { canvas.circles(instances) }

    /// Draws circle instances held in a GPU buffer in a single batch.
    /// - Parameters:
    ///   - instances: The GPU buffer holding the `CircleInstance` values.
    ///   - count: The number of instances to draw. When omitted, the whole buffer is used.
    public func circles(_ instances: GPUBuffer<CircleInstance>, count: Int? = nil) {
        canvas.circles(instances, count: count)
    }

    /// Draws a line between two points.
    /// - Parameters:
    ///   - x1: The start x.
    ///   - y1: The start y.
    ///   - x2: The end x.
    ///   - y2: The end y.
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        canvas.line(x1, y1, x2, y2)
    }

    /// Draws a triangle.
    /// - Parameters:
    ///   - x1: The first vertex x.
    ///   - y1: The first vertex y.
    ///   - x2: The second vertex x.
    ///   - y2: The second vertex y.
    ///   - x3: The third vertex x.
    ///   - y3: The third vertex y.
    public func triangle(
        _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float
    ) { canvas.triangle(x1, y1, x2, y2, x3, y3) }

    /// Draws a quad.
    /// - Parameters:
    ///   - x1: The first vertex x.
    ///   - y1: The first vertex y.
    ///   - x2: The second vertex x.
    ///   - y2: The second vertex y.
    ///   - x3: The third vertex x.
    ///   - y3: The third vertex y.
    ///   - x4: The fourth vertex x.
    ///   - y4: The fourth vertex y.
    public func quad(
        _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float,
        _ y4: Float
    ) { canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4) }

    /// Draws a point.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    public func point(_ x: Float, _ y: Float) { canvas.point(x, y) }

    /// Draws an arc.
    /// - Parameters:
    ///   - x: The x coordinate of the center.
    ///   - y: The y coordinate of the center.
    ///   - w: The width.
    ///   - h: The height.
    ///   - startAngle: The start angle in radians.
    ///   - stopAngle: The stop angle in radians. Nothing is drawn when it is less than or
    ///     equal to `startAngle`.
    ///   - mode: The arc drawing mode. When omitted, the fill is a pie slice and the
    ///     stroke is the arc only.
    ///
    /// Angles are normalized as in Processing (`stopAngle <= startAngle` draws nothing,
    /// and values beyond 2π are clamped to 0–2π).
    public func arc(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float, _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .default
    ) { canvas.arc(x, y, w, h, startAngle, stopAngle, mode) }

    /// Draws a polygon from an array of points.
    /// - Parameter points: An array of (x, y) tuples defining the polygon vertices.
    public func polygon(_ points: [(Float, Float)]) { canvas.polygon(points) }

    /// Draws a rectangle filled with a linear gradient.
    ///
    /// It does not use the current ``fill(_:)-(Color)`` or ``rectMode(_:)``: it draws with
    /// the two colors passed in, as a rectangle whose origin is its top-left corner.
    ///
    /// - Parameters:
    ///   - x: The x coordinate of the rectangle.
    ///   - y: The y coordinate of the rectangle.
    ///   - w: The width of the rectangle.
    ///   - h: The height of the rectangle.
    ///   - color1: The start color of the gradient.
    ///   - color2: The end color of the gradient.
    ///   - axis: The direction of the gradient.
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ color1: Color, _ color2: Color,
        axis: GradientAxis = .vertical
    ) { canvas.linearGradient(x, y, w, h, color1, color2, axis: axis) }

    /// Draws a radial gradient at the given center point.
    /// - Parameters:
    ///   - cx: The x coordinate of the center.
    ///   - cy: The y coordinate of the center.
    ///   - radius: The outer radius of the gradient.
    ///   - innerColor: The color at the center.
    ///   - outerColor: The color at the outer edge.
    ///   - segments: The number of segments used to approximate the circle.
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) { canvas.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments) }

    /// Draws a cubic Bézier curve.
    /// - Parameters:
    ///   - x1: The start x.
    ///   - y1: The start y.
    ///   - cx1: The first control point x.
    ///   - cy1: The first control point y.
    ///   - cx2: The second control point x.
    ///   - cy2: The second control point y.
    ///   - x2: The end x.
    ///   - y2: The end y.
    public func bezier(
        _ x1: Float, _ y1: Float, _ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) { canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2) }

    /// Draws a Catmull-Rom spline curve.
    /// - Parameters:
    ///   - x1: The first control point x.
    ///   - y1: The first control point y.
    ///   - x2: The start x.
    ///   - y2: The start y.
    ///   - x3: The end x.
    ///   - y3: The end y.
    ///   - x4: The second control point x.
    ///   - y4: The second control point y.
    public func curve(
        _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float,
        _ y4: Float
    ) { canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4) }

    /// Begins recording the vertices of a custom shape.
    /// - Parameter mode: The shape mode (polygon, triangles, and so on).
    public func beginShape(_ mode: ShapeMode = .polygon) { canvas.beginShape(mode) }

    /// Adds a vertex to the shape being recorded.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    public func vertex(_ x: Float, _ y: Float) { canvas.vertex(x, y) }

    /// Adds a cubic Bézier vertex to the current shape.
    /// - Parameters:
    ///   - cx1: The first control point x.
    ///   - cy1: The first control point y.
    ///   - cx2: The second control point x.
    ///   - cy2: The second control point y.
    ///   - x: The end x.
    ///   - y: The end y.
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x: Float, _ y: Float
    ) { canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y) }

    /// Adds a quadratic Bezier vertex to the current shape.
    /// - Parameters:
    ///   - cx: The control point x.
    ///   - cy: The control point y.
    ///   - x: The end x.
    ///   - y: The end y.
    public func quadraticVertex(_ cx: Float, _ cy: Float, _ x: Float, _ y: Float) {
        canvas.quadraticVertex(cx, cy, x, y)
    }

    /// Adds a Catmull-Rom spline vertex to the current shape.
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    public func curveVertex(_ x: Float, _ y: Float) { canvas.curveVertex(x, y) }

    /// Sets the number of segments used to approximate a curve.
    ///
    /// It affects both ``curve(_:_:_:_:_:_:_:_:)`` and ``curveVertex(_:_:)``.
    /// - Parameter n: The number of segments (values below 1 are rounded up to 1).
    public func curveDetail(_ n: Int) { canvas.curveDetail(n) }

    /// Sets the number of segments used to approximate a cubic Bezier.
    ///
    /// It affects both ``bezier(_:_:_:_:_:_:_:_:)`` and ``bezierVertex(_:_:_:_:_:_:)``.
    /// - Parameter n: The number of segments (values below 1 are rounded up to 1).
    public func bezierDetail(_ n: Int) { canvas.bezierDetail(n) }

    /// Sets the tightness of Catmull-Rom spline curves.
    ///
    /// It affects both ``curve(_:_:_:_:_:_:_:_:)`` and ``curveVertex(_:_:)``.
    /// - Parameter t: The tightness value (0 is the standard Catmull-Rom, and 1 gives a
    ///   straight line joining the two points).
    public func curveTightness(_ t: Float) { canvas.curveTightness(t) }

    /// Begins recording a contour (a hole) in the current shape.
    ///
    /// It takes effect only between ``beginShape(_:)`` and ``endShape(_:)``.
    public func beginContour() { canvas.beginContour() }

    /// Ends recording the current contour (hole).
    ///
    /// A contour with fewer than three vertices is discarded.
    public func endContour() { canvas.endContour() }

    /// Ends vertex recording and draws the current shape.
    /// - Parameter close: Whether to close the shape.
    public func endShape(_ close: CloseMode = .open) { canvas.endShape(close) }

    /// Draws an image at its original size.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    public func image(_ img: MImage, _ x: Float, _ y: Float) { canvas.image(img, x, y) }

    /// Draws an image at the given size.
    /// - Parameters:
    ///   - img: The image to draw.
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    ///   - w: The width.
    ///   - h: The height.
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(img, x, y, w, h)
    }

    /// Sets the text size.
    /// - Parameter size: The font size in points.
    public func textSize(_ size: Float) { canvas.textSize(size) }

    /// Sets the font family.
    ///
    /// - Note: A style-qualified name such as `"Helvetica Neue Bold"` also resolves, but which
    ///   ones exist depends on the font. Prefer ``textStyle(_:)``, which warns when the style is
    ///   unavailable instead of falling back to a different font.
    ///
    /// - Parameter family: The font family name.
    public func textFont(_ family: String) { canvas.textFont(family) }

    /// Sets the bold / italic style applied on top of the current font.
    ///
    /// - Note: A style the current font has no face for leaves the text unstyled and warns.
    ///
    /// - Parameter style: The style to apply.
    public func textStyle(_ style: TextStyle) { canvas.textStyle(style) }

    /// Sets the text alignment.
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        canvas.textAlign(horizontal, vertical)
    }

    /// Sets the text leading (line height).
    ///
    /// It is in pixels and is the distance between the baselines of adjacent lines.
    /// Calling ``textSize(_:)`` or ``textFont(_:)`` resets it to the default.
    ///
    /// - Parameter leading: The line height in pixels.
    public func textLeading(_ leading: Float) { canvas.textLeading(leading) }

    /// Chooses where the rectangle form of ``text(_:_:_:_:_:)`` may break a line.
    ///
    /// - Note: It has no effect on ``text(_:_:_:)``, which breaks only at newlines.
    ///
    /// - Parameter mode: The wrap rule.
    public func textWrap(_ mode: TextWrap) { canvas.textWrap(mode) }

    /// Draws a text string at the given position.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) { canvas.text(string, x, y) }

    /// Draws a text string inside a bounding box.
    ///
    /// It wraps automatically at the width of the box, and the line height follows
    /// ``textLeading(_:)``. Lines that do not fit within the height of the box are not
    /// drawn.
    ///
    /// Color is handled the same way as in ``text(_:_:_:)``, and ``noFill()`` has no
    /// effect on text.
    ///
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: The x coordinate of the bounding box.
    ///   - y: The y coordinate of the bounding box.
    ///   - w: The width of the bounding box.
    ///   - h: The height of the bounding box.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.text(string, x, y, w, h)
    }

    /// Returns the width of a text string (the sum of the per-character advances).
    /// - Parameter string: The text to measure.
    /// - Returns: The width in pixels.
    public func textWidth(_ string: String) -> Float { canvas.textWidth(string) }

    /// Returns the rectangle ``text(_:_:_:)`` would fill for this string at `(x, y)`.
    ///
    /// - Note: The width is the advance sum ``textWidth(_:)`` reports, not the extent of the ink.
    ///
    /// - Parameters:
    ///   - string: The text to measure.
    ///   - x: The x coordinate the text would be drawn at.
    ///   - y: The y coordinate the text would be drawn at.
    /// - Returns: The box, with `x` / `y` at its top-left corner.
    public func textBounds(_ string: String, _ x: Float, _ y: Float) -> TextBounds {
        canvas.textBounds(string, x, y)
    }

    /// Returns the ascent of the current font.
    /// - Returns: The font ascent in pixels.
    public func textAscent() -> Float { canvas.textAscent() }

    /// Returns the descent of the current font.
    /// - Returns: The font descent in pixels.
    public func textDescent() -> Float { canvas.textDescent() }

    /// Returns the glyph outlines of text as one closed polyline per contour.
    ///
    /// The coordinates are this buffer's pixel coordinates, and the current
    /// ``textSize(_:)`` / ``textFont(_:)`` / ``textAlign(_:_:)`` / ``textLeading(_:)``
    /// are interpreted the same way as in ``text(_:_:_:)``.
    ///
    /// - Parameters:
    ///   - string: The text to take the outlines from.
    ///   - x: The x coordinate of the text (the same meaning as in `text()`).
    ///   - y: The y coordinate of the text (the same meaning as in `text()`).
    ///   - sampleFactor: How finely curves are subdivided into line segments. Larger
    ///     values produce more points.
    /// - Returns: One polyline per contour. An empty array for an empty string, or for
    ///   text made only of characters that have no contours.
    public func textToContours(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [[Vec2]] { canvas.textToContours(string, x, y, sampleFactor: sampleFactor) }

    /// Returns the points on the glyph outlines of text as a single array.
    ///
    /// The boundaries between contours are lost. To work with each contour separately,
    /// use ``textToContours(_:_:_:sampleFactor:)``.
    ///
    /// - Parameters:
    ///   - string: The text to take the outlines from.
    ///   - x: The x coordinate of the text (the same meaning as in `text()`).
    ///   - y: The y coordinate of the text (the same meaning as in `text()`).
    ///   - sampleFactor: How finely curves are subdivided into line segments. Larger
    ///     values produce more points.
    /// - Returns: The points on the outlines.
    public func textToPoints(
        _ string: String, _ x: Float, _ y: Float, sampleFactor: Float = 0.25
    ) -> [Vec2] { canvas.textToPoints(string, x, y, sampleFactor: sampleFactor) }
}
