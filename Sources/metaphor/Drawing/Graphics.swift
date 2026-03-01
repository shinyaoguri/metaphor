import Metal
import simd

/// オフスクリーン描画バッファ（Processing の createGraphics() に相当）
///
/// 独自のCanvas2Dを持ち、メインキャンバスとは独立して描画できる。
/// 描画結果はMImageとして取り出し、メインキャンバスに `image()` で描画可能。
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

    /// 幅（ピクセル）
    public var width: Float { canvas.width }

    /// 高さ（ピクセル）
    public var height: Float { canvas.height }

    /// 内部テクスチャ（MImageとして取り出す用）
    public var texture: MTLTexture { textureManager.colorTexture }

    // MARK: - Initialization

    init(device: MTLDevice, shaderLibrary: ShaderLibrary, depthStencilCache: DepthStencilCache, width: Int, height: Int) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw GraphicsError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        self.textureManager = TextureManager(device: device, width: width, height: height)
        self.canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLibrary,
            depthStencilCache: depthStencilCache,
            width: Float(width),
            height: Float(height)
        )
    }

    // MARK: - Draw Lifecycle

    /// 描画開始（command buffer + encoder を作成）
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

    /// 描画終了（flush → commit → GPU完了を待つ）
    public func endDraw() {
        canvas.end()
        encoder?.endEncoding()
        encoder = nil
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// テクスチャをMImageとして取得
    public func toImage() -> MImage {
        MImage(texture: textureManager.colorTexture)
    }

    // MARK: - Drawing Methods (Canvas2D転送)

    public func background(_ color: Color) { canvas.background(color) }
    public func background(_ gray: Float) { canvas.background(gray) }
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.background(v1, v2, v3, a) }

    public func fill(_ color: Color) { canvas.fill(color) }
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.fill(v1, v2, v3, a) }
    public func fill(_ gray: Float) { canvas.fill(gray) }
    public func fill(_ gray: Float, _ alpha: Float) { canvas.fill(gray, alpha) }
    public func noFill() { canvas.noFill() }

    public func stroke(_ color: Color) { canvas.stroke(color) }
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.stroke(v1, v2, v3, a) }
    public func stroke(_ gray: Float) { canvas.stroke(gray) }
    public func stroke(_ gray: Float, _ alpha: Float) { canvas.stroke(gray, alpha) }
    public func noStroke() { canvas.noStroke() }
    public func strokeWeight(_ weight: Float) { canvas.strokeWeight(weight) }

    public func blendMode(_ mode: BlendMode) { canvas.blendMode(mode) }
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) { canvas.colorMode(space, max1, max2, max3, maxA) }
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas.colorMode(space, maxAll) }

    public func rectMode(_ mode: RectMode) { canvas.rectMode(mode) }
    public func ellipseMode(_ mode: EllipseMode) { canvas.ellipseMode(mode) }
    public func imageMode(_ mode: ImageMode) { canvas.imageMode(mode) }

    public func tint(_ color: Color) { canvas.tint(color) }
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.tint(v1, v2, v3, a) }
    public func noTint() { canvas.noTint() }

    public func push() { canvas.push() }
    public func pop() { canvas.pop() }
    public func translate(_ x: Float, _ y: Float) { canvas.translate(x, y) }
    public func rotate(_ angle: Float) { canvas.rotate(angle) }
    public func scale(_ sx: Float, _ sy: Float) { canvas.scale(sx, sy) }
    public func scale(_ s: Float) { canvas.scale(s) }

    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.rect(x, y, w, h) }
    public func square(_ x: Float, _ y: Float, _ size: Float) { canvas.square(x, y, size) }
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.ellipse(x, y, w, h) }
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) { canvas.circle(x, y, diameter) }
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) { canvas.line(x1, y1, x2, y2) }
    public func triangle(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) { canvas.triangle(x1, y1, x2, y2, x3, y3) }
    public func quad(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float, _ y4: Float) { canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4) }
    public func point(_ x: Float, _ y: Float) { canvas.point(x, y) }
    public func arc(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ startAngle: Float, _ stopAngle: Float, _ mode: ArcMode = .open) { canvas.arc(x, y, w, h, startAngle, stopAngle, mode) }
    public func polygon(_ points: [(Float, Float)]) { canvas.polygon(points) }

    public func bezier(_ x1: Float, _ y1: Float, _ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x2: Float, _ y2: Float) { canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2) }
    public func curve(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float, _ y4: Float) { canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4) }

    public func beginShape(_ mode: ShapeMode = .polygon) { canvas.beginShape(mode) }
    public func vertex(_ x: Float, _ y: Float) { canvas.vertex(x, y) }
    public func bezierVertex(_ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x: Float, _ y: Float) { canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y) }
    public func curveVertex(_ x: Float, _ y: Float) { canvas.curveVertex(x, y) }
    public func endShape(_ close: CloseMode = .open) { canvas.endShape(close) }

    public func image(_ img: MImage, _ x: Float, _ y: Float) { canvas.image(img, x, y) }
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.image(img, x, y, w, h) }

    public func textSize(_ size: Float) { canvas.textSize(size) }
    public func textFont(_ family: String) { canvas.textFont(family) }
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) { canvas.textAlign(horizontal, vertical) }
    public func text(_ string: String, _ x: Float, _ y: Float) { canvas.text(string, x, y) }
    public func textWidth(_ string: String) -> Float { canvas.textWidth(string) }
}

// MARK: - Errors

public enum GraphicsError: Error {
    case commandQueueCreationFailed
}
