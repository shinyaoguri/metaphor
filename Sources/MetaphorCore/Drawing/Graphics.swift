import Metal
import simd

/// オフスクリーン2D描画バッファを提供します（Processing の `createGraphics()` に相当）。
///
/// 独立した Canvas2D を所有し、メインキャンバスとは別に描画できます。
/// 結果は MImage として取得し、`image()` でメインキャンバスに描画できます。
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

    /// 幅をピクセル単位で返します。
    public var width: Float { canvas.width }

    /// 高さをピクセル単位で返します。
    public var height: Float { canvas.height }

    /// MImage 取得用の内部カラーテクスチャを返します。
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

    /// コマンドバッファとレンダーコマンドエンコーダーを作成して描画を開始します。
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

    /// フラッシュ、コミット、GPU完了待機により描画を終了します。
    public func endDraw() {
        canvas.end()
        encoder?.endEncoding()
        encoder = nil
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// オフスクリーンテクスチャを MImage として返します。
    /// - Returns: 内部カラーテクスチャをラップした MImage。
    public func toImage() -> MImage {
        MImage(texture: textureManager.colorTexture)
    }

    // MARK: - Drawing Methods (forwarded to Canvas2D)

    /// 背景色を設定します。
    /// - Parameter color: 背景色。
    public func background(_ color: Color) { canvas.background(color) }

    /// 背景をグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func background(_ gray: Float) { canvas.background(gray) }

    /// チャンネル値で背景色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.background(v1, v2, v3, a) }

    /// 塗りつぶし色を設定します。
    /// - Parameter color: 塗りつぶし色。
    public func fill(_ color: Color) { canvas.fill(color) }

    /// チャンネル値で塗りつぶし色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.fill(v1, v2, v3, a) }

    /// 塗りつぶしをグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func fill(_ gray: Float) { canvas.fill(gray) }

    /// 塗りつぶしをグレースケール値とアルファで設定します。
    /// - Parameters:
    ///   - gray: グレースケール値。
    ///   - alpha: アルファ値。
    public func fill(_ gray: Float, _ alpha: Float) { canvas.fill(gray, alpha) }

    /// シェイプの塗りつぶしを無効にします。
    public func noFill() { canvas.noFill() }

    /// ストローク色を設定します。
    /// - Parameter color: ストローク色。
    public func stroke(_ color: Color) { canvas.stroke(color) }

    /// チャンネル値でストローク色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.stroke(v1, v2, v3, a) }

    /// ストロークをグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func stroke(_ gray: Float) { canvas.stroke(gray) }

    /// ストロークをグレースケール値とアルファで設定します。
    /// - Parameters:
    ///   - gray: グレースケール値。
    ///   - alpha: アルファ値。
    public func stroke(_ gray: Float, _ alpha: Float) { canvas.stroke(gray, alpha) }

    /// シェイプのストロークを無効にします。
    public func noStroke() { canvas.noStroke() }

    /// ストロークの太さを設定します。
    /// - Parameter weight: ストロークの太さ（ピクセル単位）。
    public func strokeWeight(_ weight: Float) { canvas.strokeWeight(weight) }

    /// ストロークキャップスタイルを設定します。
    /// - Parameter cap: キャップスタイル。
    public func strokeCap(_ cap: StrokeCap) { canvas.strokeCap(cap) }

    /// ストロークジョインスタイルを設定します。
    /// - Parameter join: ジョインスタイル。
    public func strokeJoin(_ join: StrokeJoin) { canvas.strokeJoin(join) }

    /// 後続の描画操作のブレンドモードを設定します。
    /// - Parameter mode: ブレンドモード。
    public func blendMode(_ mode: BlendMode) { canvas.blendMode(mode) }

    /// カラーモードとオプションの最大チャンネル値を設定します。
    /// - Parameters:
    ///   - space: カラースペース（RGB または HSB）。
    ///   - max1: 第1チャンネルの最大値。
    ///   - max2: 第2チャンネルの最大値。
    ///   - max3: 第3チャンネルの最大値。
    ///   - maxA: アルファチャンネルの最大値。
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) { canvas.colorMode(space, max1, max2, max3, maxA) }

    /// 全チャンネルに均一な最大値を持つカラーモードを設定します。
    /// - Parameters:
    ///   - space: カラースペース。
    ///   - maxAll: 全チャンネルに適用される最大値。
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas.colorMode(space, maxAll) }

    /// 矩形の描画モードを設定します。
    /// - Parameter mode: 矩形モード。
    public func rectMode(_ mode: RectMode) { canvas.rectMode(mode) }

    /// 楕円の描画モードを設定します。
    /// - Parameter mode: 楕円モード。
    public func ellipseMode(_ mode: EllipseMode) { canvas.ellipseMode(mode) }

    /// 画像の描画モードを設定します。
    /// - Parameter mode: 画像モード。
    public func imageMode(_ mode: ImageMode) { canvas.imageMode(mode) }

    /// 画像のティント色を設定します。
    /// - Parameter color: ティント色。
    public func tint(_ color: Color) { canvas.tint(color) }

    /// チャンネル値でティント色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas.tint(v1, v2, v3, a) }

    /// 画像のティントを無効にします。
    public func noTint() { canvas.noTint() }

    /// 現在の描画状態（スタイルとトランスフォーム）をスタックにプッシュします。
    public func push() { canvas.push() }

    /// 最後に保存した描画状態（スタイルとトランスフォーム）をスタックからポップします。
    public func pop() { canvas.pop() }

    /// 指定されたオフセットで座標系を平行移動します。
    /// - Parameters:
    ///   - x: 水平オフセット。
    ///   - y: 垂直オフセット。
    public func translate(_ x: Float, _ y: Float) { canvas.translate(x, y) }

    /// ラジアン単位の角度で座標系を回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotate(_ angle: Float) { canvas.rotate(angle) }

    /// 指定されたファクターで座標系をスケーリングします。
    /// - Parameters:
    ///   - sx: 水平スケールファクター。
    ///   - sy: 垂直スケールファクター。
    public func scale(_ sx: Float, _ sy: Float) { canvas.scale(sx, sy) }

    /// 座標系を均一にスケーリングします。
    /// - Parameter s: 均一スケールファクター。
    public func scale(_ s: Float) { canvas.scale(s) }

    /// 矩形を描画します。
    /// - Parameters:
    ///   - x: X座標。
    ///   - y: Y座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.rect(x, y, w, h) }

    /// 正方形を描画します。
    /// - Parameters:
    ///   - x: X座標。
    ///   - y: Y座標。
    ///   - size: 辺の長さ。
    public func square(_ x: Float, _ y: Float, _ size: Float) { canvas.square(x, y, size) }

    /// 楕円を描画します。
    /// - Parameters:
    ///   - x: X座標。
    ///   - y: Y座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.ellipse(x, y, w, h) }

    /// 円を描画します。
    /// - Parameters:
    ///   - x: 中心のX座標。
    ///   - y: 中心のY座標。
    ///   - diameter: 円の直径。
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) { canvas.circle(x, y, diameter) }

    /// 2点間に線を描画します。
    /// - Parameters:
    ///   - x1: 始点X。
    ///   - y1: 始点Y。
    ///   - x2: 終点X。
    ///   - y2: 終点Y。
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) { canvas.line(x1, y1, x2, y2) }

    /// 三角形を描画します。
    /// - Parameters:
    ///   - x1: 第1頂点X。
    ///   - y1: 第1頂点Y。
    ///   - x2: 第2頂点X。
    ///   - y2: 第2頂点Y。
    ///   - x3: 第3頂点X。
    ///   - y3: 第3頂点Y。
    public func triangle(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) { canvas.triangle(x1, y1, x2, y2, x3, y3) }

    /// 四角形を描画します。
    /// - Parameters:
    ///   - x1: 第1頂点X。
    ///   - y1: 第1頂点Y。
    ///   - x2: 第2頂点X。
    ///   - y2: 第2頂点Y。
    ///   - x3: 第3頂点X。
    ///   - y3: 第3頂点Y。
    ///   - x4: 第4頂点X。
    ///   - y4: 第4頂点Y。
    public func quad(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float, _ y4: Float) { canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4) }

    /// 点を描画します。
    /// - Parameters:
    ///   - x: X座標。
    ///   - y: Y座標。
    public func point(_ x: Float, _ y: Float) { canvas.point(x, y) }

    /// 弧を描画します。
    /// - Parameters:
    ///   - x: 中心のX座標。
    ///   - y: 中心のY座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - startAngle: ラジアン単位の開始角度。
    ///   - stopAngle: ラジアン単位の終了角度。
    ///   - mode: 弧の描画モード。
    public func arc(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ startAngle: Float, _ stopAngle: Float, _ mode: ArcMode = .open) { canvas.arc(x, y, w, h, startAngle, stopAngle, mode) }

    /// ポイント配列からポリゴンを描画します。
    /// - Parameter points: ポリゴン頂点を定義する (x, y) タプルの配列。
    public func polygon(_ points: [(Float, Float)]) { canvas.polygon(points) }

    /// 三次ベジェ曲線を描画します。
    /// - Parameters:
    ///   - x1: 始点X。
    ///   - y1: 始点Y。
    ///   - cx1: 第1制御点X。
    ///   - cy1: 第1制御点Y。
    ///   - cx2: 第2制御点X。
    ///   - cy2: 第2制御点Y。
    ///   - x2: 終点X。
    ///   - y2: 終点Y。
    public func bezier(_ x1: Float, _ y1: Float, _ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x2: Float, _ y2: Float) { canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2) }

    /// Catmull-Rom スプライン曲線を描画します。
    /// - Parameters:
    ///   - x1: 第1制御点X。
    ///   - y1: 第1制御点Y。
    ///   - x2: 始点X。
    ///   - y2: 始点Y。
    ///   - x3: 終点X。
    ///   - y3: 終点Y。
    ///   - x4: 第2制御点X。
    ///   - y4: 第2制御点Y。
    public func curve(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float, _ x4: Float, _ y4: Float) { canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4) }

    /// カスタムシェイプの頂点記録を開始します。
    /// - Parameter mode: シェイプモード（polygon、triangles など）。
    public func beginShape(_ mode: ShapeMode = .polygon) { canvas.beginShape(mode) }

    /// 記録中のシェイプに頂点を追加します。
    /// - Parameters:
    ///   - x: X座標。
    ///   - y: Y座標。
    public func vertex(_ x: Float, _ y: Float) { canvas.vertex(x, y) }

    /// 現在のシェイプに三次ベジェ頂点を追加します。
    /// - Parameters:
    ///   - cx1: 第1制御点X。
    ///   - cy1: 第1制御点Y。
    ///   - cx2: 第2制御点X。
    ///   - cy2: 第2制御点Y。
    ///   - x: 終点X。
    ///   - y: 終点Y。
    public func bezierVertex(_ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x: Float, _ y: Float) { canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y) }

    /// 現在のシェイプに Catmull-Rom スプライン頂点を追加します。
    /// - Parameters:
    ///   - x: X座標。
    ///   - y: Y座標。
    public func curveVertex(_ x: Float, _ y: Float) { canvas.curveVertex(x, y) }

    /// 頂点の記録を終了し、現在のシェイプを描画します。
    /// - Parameter close: シェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) { canvas.endShape(close) }

    /// 画像を元のサイズで描画します。
    /// - Parameters:
    ///   - img: 描画する画像。
    ///   - x: X座標。
    ///   - y: Y座標。
    public func image(_ img: MImage, _ x: Float, _ y: Float) { canvas.image(img, x, y) }

    /// 指定されたサイズで画像を描画します。
    /// - Parameters:
    ///   - img: 描画する画像。
    ///   - x: X座標。
    ///   - y: Y座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) { canvas.image(img, x, y, w, h) }

    /// テキストサイズを設定します。
    /// - Parameter size: ポイント単位のフォントサイズ。
    public func textSize(_ size: Float) { canvas.textSize(size) }

    /// フォントファミリーを設定します。
    /// - Parameter family: フォントファミリー名。
    public func textFont(_ family: String) { canvas.textFont(family) }

    /// テキストの配置を設定します。
    /// - Parameters:
    ///   - horizontal: 水平方向の配置。
    ///   - vertical: 垂直方向の配置。
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) { canvas.textAlign(horizontal, vertical) }

    /// 指定位置にテキスト文字列を描画します。
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: X座標。
    ///   - y: Y座標。
    public func text(_ string: String, _ x: Float, _ y: Float) { canvas.text(string, x, y) }

    /// テキスト文字列のレンダリング幅を返します。
    /// - Parameter string: 計測するテキスト。
    /// - Returns: ピクセル単位の幅。
    public func textWidth(_ string: String) -> Float { canvas.textWidth(string) }

    /// 現在のフォントのアセントを返します。
    /// - Returns: ピクセル単位のフォントアセント。
    public func textAscent() -> Float { canvas.textAscent() }

    /// 現在のフォントのディセントを返します。
    /// - Returns: ピクセル単位のフォントディセント。
    public func textDescent() -> Float { canvas.textDescent() }
}
