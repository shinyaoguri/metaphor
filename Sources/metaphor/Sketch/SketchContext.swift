#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import Metal
import simd

/// Sketch内で使う描画コンテキスト
///
/// Canvas2D/Canvas3Dの描画メソッドを転送し、時間・入力などの便利プロパティを提供する。
/// 上級者向けに `renderer`, `encoder`, `canvas`, `canvas3D` へのエスケープハッチも用意。
@MainActor
public final class SketchContext {
    // MARK: - Public Properties

    /// キャンバスの幅（ピクセル）
    public private(set) var width: Float

    /// キャンバスの高さ（ピクセル）
    public private(set) var height: Float

    /// 経過時間（秒）
    public var time: Float = 0

    /// フレーム間の時間（秒）
    public var deltaTime: Float = 0

    /// フレーム番号
    public var frameCount: Int = 0

    /// 入力マネージャ
    public let input: InputManager

    // MARK: - Escape Hatches

    /// MetaphorRenderer（上級者向け）
    public let renderer: MetaphorRenderer

    /// 現在のレンダーコマンドエンコーダ（フレーム中のみ有効）
    public var encoder: MTLRenderCommandEncoder? { canvas.currentEncoder }

    /// Canvas2D（上級者向け）
    public private(set) var canvas: Canvas2D

    /// Canvas3D（上級者向け）
    public private(set) var canvas3D: Canvas3D

    // MARK: - Animation Control

    /// ループ中かどうか
    public private(set) var isLooping: Bool = true

    /// loop() コールバック（SketchRunnerが設定）
    var onLoop: (() -> Void)?

    /// noLoop() コールバック（SketchRunnerが設定）
    var onNoLoop: (() -> Void)?

    /// redraw() コールバック（SketchRunnerが設定）
    var onRedraw: (() -> Void)?

    /// frameRate() コールバック（SketchRunnerが設定）
    var onFrameRate: ((Int) -> Void)?

    /// アニメーションを再開
    public func loop() {
        isLooping = true
        onLoop?()
    }

    /// アニメーションを停止
    public func noLoop() {
        isLooping = false
        onNoLoop?()
    }

    /// 1フレームだけ描画（noLoop時に使用）
    public func redraw() {
        onRedraw?()
    }

    /// フレームレートを動的に変更
    public func frameRate(_ fps: Int) {
        onFrameRate?(fps)
    }

    // MARK: - Cursor Control

    /// カーソルを表示
    public func cursor() {
        NSCursor.unhide()
    }

    /// カーソルを非表示
    public func noCursor() {
        NSCursor.hide()
    }

    // MARK: - Canvas Resize

    /// createCanvas コールバック（SketchRunnerが設定）
    var onCreateCanvas: ((Int, Int) -> Void)?

    /// キャンバスサイズを設定（setup()内で呼ぶ）
    public func createCanvas(width: Int, height: Int) {
        onCreateCanvas?(width, height)
    }

    /// キャンバスを再構築（内部用）
    func rebuildCanvas(canvas: Canvas2D, canvas3D: Canvas3D) {
        self.canvas = canvas
        self.canvas3D = canvas3D
        self.width = canvas.width
        self.height = canvas.height
    }

    // MARK: - Tween Manager

    /// Tween 自動更新マネージャー
    public let tweenManager = TweenManager()

    // MARK: - GUI

    /// パラメータ GUI インスタンス
    public let gui = ParameterGUI()

    // MARK: - Performance HUD

    /// パフォーマンス HUD（nil なら無効）
    private var performanceHUD: PerformanceHUD?

    /// パフォーマンス HUD を有効化
    public func enablePerformanceHUD() {
        if performanceHUD == nil {
            performanceHUD = PerformanceHUD()
        }
    }

    /// パフォーマンス HUD を無効化
    public func disablePerformanceHUD() {
        performanceHUD = nil
    }

    // MARK: - Compute State (internal)

    /// 現在のコマンドバッファ（コンピュートフェーズ中のみ有効）
    private var _commandBuffer: MTLCommandBuffer?

    /// 遅延作成されるコンピュートエンコーダ
    private var _computeEncoder: MTLComputeCommandEncoder?

    // MARK: - Initialization

    init(renderer: MetaphorRenderer, canvas: Canvas2D, canvas3D: Canvas3D, input: InputManager) {
        self.renderer = renderer
        self.canvas = canvas
        self.canvas3D = canvas3D
        self.input = input
        self.width = canvas.width
        self.height = canvas.height
    }

    // MARK: - Compute Frame Management (internal)

    /// コンピュートフェーズ開始
    func beginCompute(commandBuffer: MTLCommandBuffer, time: Float, deltaTime: Float) {
        self._commandBuffer = commandBuffer
        self.time = time
        self.deltaTime = deltaTime
    }

    /// コンピュートフェーズ終了（エンコーダがある場合のみendEncoding）
    func endCompute() {
        _computeEncoder?.endEncoding()
        _computeEncoder = nil
        _commandBuffer = nil
    }

    // MARK: - Frame Management (internal)

    func beginFrame(encoder: MTLRenderCommandEncoder, time: Float, deltaTime: Float) {
        self.time = time
        self.deltaTime = deltaTime
        self.frameCount += 1
        tweenManager.update(deltaTime)
        canvas3D.begin(encoder: encoder, time: time, bufferIndex: renderer.frameBufferIndex)
        canvas.begin(encoder: encoder, bufferIndex: renderer.frameBufferIndex)
    }

    func endFrame() {
        // Performance HUD overlay (before canvas.end() so it's drawn on top)
        if let hud = performanceHUD {
            hud.update(deltaTime: deltaTime)
            hud.updateGPUTime(start: renderer.lastGPUStartTime, end: renderer.lastGPUEndTime)
            hud.draw(canvas: canvas, width: Float(renderer.textureManager.width), height: Float(renderer.textureManager.height))
        }
        canvas3D.end()
        canvas.end()
        // GIF frame capture
        captureGIFFrame()
    }

    // MARK: - Shape Mode Settings

    /// 矩形の座標解釈モードを設定
    public func rectMode(_ mode: RectMode) {
        canvas.rectMode(mode)
    }

    /// 楕円の座標解釈モードを設定
    public func ellipseMode(_ mode: EllipseMode) {
        canvas.ellipseMode(mode)
    }

    /// 画像の座標解釈モードを設定
    public func imageMode(_ mode: ImageMode) {
        canvas.imageMode(mode)
    }

    // MARK: - Drawing Style

    /// 現在の共通描画スタイルを取得
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

    /// 色空間と最大値を設定（2D/3D両方に反映）
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        canvas.colorMode(space, max1, max2, max3, maxA)
        canvas3D.colorMode(space, max1, max2, max3, maxA)
    }

    /// 色空間と均一な最大値を設定（2D/3D両方に反映）
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        canvas.colorMode(space, maxAll)
        canvas3D.colorMode(space, maxAll)
    }

    // MARK: - Background

    /// 背景を塗りつぶす
    public func background(_ color: Color) {
        canvas.background(color)
    }

    /// グレースケール背景
    public func background(_ gray: Float) {
        canvas.background(gray)
    }

    /// 背景色を設定（colorModeに従って解釈）
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.background(v1, v2, v3, a)
    }

    // MARK: - Style (2D + 3D共有)

    /// 塗りつぶし色を設定（2D/3D両方に反映）
    public func fill(_ color: Color) {
        canvas.fill(color)
        canvas3D.fill(color)
    }

    /// 塗りつぶし色を設定（colorModeに従って解釈、2D/3D両方に反映）
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.fill(v1, v2, v3, a)
        canvas3D.fill(v1, v2, v3, a)
    }

    /// グレースケールで塗りつぶし色を設定（2D/3D両方に反映）
    public func fill(_ gray: Float) {
        canvas.fill(gray)
        canvas3D.fill(gray)
    }

    /// グレースケール＋アルファで塗りつぶし色を設定（2D/3D両方に反映）
    public func fill(_ gray: Float, _ alpha: Float) {
        canvas.fill(gray, alpha)
        canvas3D.fill(gray, alpha)
    }

    /// 塗りつぶしなし（2D/3D両方に反映）
    public func noFill() {
        canvas.noFill()
        canvas3D.noFill()
    }

    /// 線の色を設定（2D/3D両方に反映）
    public func stroke(_ color: Color) {
        canvas.stroke(color)
        canvas3D.stroke(color)
    }

    /// 線の色を設定（colorModeに従って解釈、2D/3D両方に反映）
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.stroke(v1, v2, v3, a)
        canvas3D.stroke(v1, v2, v3, a)
    }

    /// グレースケールで線の色を設定（2D/3D両方に反映）
    public func stroke(_ gray: Float) {
        canvas.stroke(gray)
        canvas3D.stroke(gray)
    }

    /// グレースケール＋アルファで線の色を設定（2D/3D両方に反映）
    public func stroke(_ gray: Float, _ alpha: Float) {
        canvas.stroke(gray, alpha)
        canvas3D.stroke(gray, alpha)
    }

    /// 線なし（2D/3D両方に反映）
    public func noStroke() {
        canvas.noStroke()
        canvas3D.noStroke()
    }

    /// 線の太さを設定（2Dのみ）
    public func strokeWeight(_ weight: Float) {
        canvas.strokeWeight(weight)
    }

    /// ストロークの端点スタイルを設定
    public func strokeCap(_ cap: StrokeCap) {
        canvas.strokeCap(cap)
    }

    /// ストロークの接合スタイルを設定
    public func strokeJoin(_ join: StrokeJoin) {
        canvas.strokeJoin(join)
    }

    /// ブレンドモードを設定
    public func blendMode(_ mode: BlendMode) {
        canvas.blendMode(mode)
    }

    // MARK: - Tint

    /// 画像のティント色を設定
    public func tint(_ color: Color) {
        canvas.tint(color)
    }

    /// 画像のティント色を設定（colorModeに従って解釈）
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.tint(v1, v2, v3, a)
    }

    /// グレースケールでティント色を設定
    public func tint(_ gray: Float) {
        canvas.tint(gray)
    }

    /// グレースケール＋アルファでティント色を設定
    public func tint(_ gray: Float, _ alpha: Float) {
        canvas.tint(gray, alpha)
    }

    /// ティントを無効化
    public func noTint() {
        canvas.noTint()
    }

    // MARK: - Image

    /// 画像を読み込み
    public func loadImage(_ path: String) throws -> MImage {
        try MImage(path: path, device: renderer.device)
    }

    /// 空の画像を作成（ピクセル操作用）
    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        MImage.createImage(width, height, device: renderer.device)
    }

    /// 画像にフィルタを適用（GPU版）
    public func filter(_ image: MImage, _ type: FilterType) {
        renderer.imageFilterGPU.apply(type, to: image)
    }

    /// オフスクリーン描画バッファを作成
    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        try? Graphics(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    /// 3D オフスクリーン描画バッファを作成
    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        try? Graphics3D(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: w,
            height: h
        )
    }

    // MARK: - Camera Capture

    /// カメラキャプチャデバイスを作成（自動で開始）
    /// - Parameters:
    ///   - width: 映像幅（デフォルト 1280）
    ///   - height: 映像高さ（デフォルト 720）
    ///   - position: カメラ位置（デフォルト .front）
    /// - Returns: CaptureDevice
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice {
        let capture = CaptureDevice(device: renderer.device, width: width, height: height, position: position)
        capture.start()
        return capture
    }

    /// CaptureDeviceの最新フレームを描画
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y)
        }
    }

    /// CaptureDeviceの最新フレームをサイズ指定で描画
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        capture.read()
        if let img = capture.toImage() {
            canvas.image(img, x, y, w, h)
        }
    }

    /// 画像を描画
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        canvas.image(img, x, y)
    }

    /// Graphicsバッファを描画
    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Graphicsバッファをサイズ指定で描画
    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// Graphics3Dバッファを描画
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        canvas.image(pg.toImage(), x, y)
    }

    /// Graphics3Dバッファをサイズ指定で描画
    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(pg.toImage(), x, y, w, h)
    }

    /// 画像をサイズ指定で描画
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(img, x, y, w, h)
    }

    /// サブイメージ描画（スプライトシート/タイルマップ用）
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        canvas.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: - Text

    /// テキストサイズを設定
    public func textSize(_ size: Float) {
        canvas.textSize(size)
    }

    /// フォントを設定
    public func textFont(_ family: String) {
        canvas.textFont(family)
    }

    /// テキスト揃えを設定
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        canvas.textAlign(horizontal, vertical)
    }

    /// テキストの行間を設定
    public func textLeading(_ leading: Float) {
        canvas.textLeading(leading)
    }

    /// テキストの描画幅を取得
    public func textWidth(_ string: String) -> Float {
        canvas.textWidth(string)
    }

    /// フォントのアセントを取得
    public func textAscent() -> Float {
        canvas.textAscent()
    }

    /// フォントのディセントを取得
    public func textDescent() -> Float {
        canvas.textDescent()
    }

    /// テキストを描画
    public func text(_ string: String, _ x: Float, _ y: Float) {
        canvas.text(string, x, y)
    }

    /// ボックス内にテキストを描画（自動折り返し）
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.text(string, x, y, w, h)
    }

    // MARK: - Screenshot

    /// スクリーンショットを保存
    public func save(_ path: String) {
        renderer.saveScreenshot(to: path)
    }

    /// 連番フレーム書き出しを開始
    /// - Parameters:
    ///   - directory: 出力先（nilならデスクトップに自動作成）
    ///   - pattern: ファイル名パターン
    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        let dir: String
        if let directory {
            dir = directory
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            dir = NSHomeDirectory() + "/Desktop/metaphor_frames_\(formatter.string(from: Date()))"
        }
        renderer.frameExporter.beginSequence(directory: dir, pattern: pattern)
    }

    /// 連番フレーム書き出しを停止
    public func endRecord() {
        renderer.frameExporter.endSequence()
    }

    /// ビデオ録画を開始
    /// - Parameters:
    ///   - path: 出力ファイルパス（nilならデスクトップに自動生成）
    ///   - config: ビデオエクスポート設定
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).\(config.format.fileExtension)"
        }
        try? renderer.videoExporter.beginRecord(
            path: actualPath,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height,
            config: config
        )
    }

    /// ビデオ録画を終了
    /// - Parameter completion: 書き出し完了時に呼ばれるコールバック
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        renderer.videoExporter.endRecord(completion: completion)
    }

    /// 現在フレームを単発で保存（Processing互換）
    public func saveFrame(_ filename: String? = nil) {
        let name: String
        if let filename {
            name = filename
        } else {
            name = "screen-\(String(format: "%04d", frameCount)).png"
        }
        let path = NSHomeDirectory() + "/Desktop/" + name
        renderer.saveScreenshot(to: path)
    }

    /// タイムスタンプ付きでデスクトップに保存
    public func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "metaphor_\(formatter.string(from: Date())).png"
        let path = NSHomeDirectory() + "/Desktop/" + name
        save(path)
    }

    // MARK: - Offline Rendering

    /// オフラインレンダリングモードかどうか
    public var isOfflineRendering: Bool {
        renderer.isOfflineRendering
    }

    /// オフラインレンダリングモードを開始
    ///
    /// フレームの経過時間が決定論的になり、フレーム落ちなしの高品質動画レンダリングが可能。
    /// - Parameter fps: フレームレート（デフォルト60）
    public func beginOfflineRender(fps: Double = 60) {
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = fps
        renderer.resetOfflineRendering()
    }

    /// オフラインレンダリングモードを終了
    public func endOfflineRender() {
        renderer.isOfflineRendering = false
    }

    // MARK: - FBO Feedback

    /// フレームバッファフィードバックを有効化
    ///
    /// 有効にすると、毎フレーム開始時に前フレームのカラーテクスチャがコピーされ、
    /// `previousFrame()` で MImage として取得できるようになる。
    public func enableFeedback() {
        renderer.feedbackEnabled = true
    }

    /// フレームバッファフィードバックを無効化
    public func disableFeedback() {
        renderer.feedbackEnabled = false
    }

    /// 前フレームのレンダリング結果を MImage として取得
    ///
    /// `enableFeedback()` を呼んだ後に使用する。
    /// フィードバック無効時または最初のフレームでは nil を返す。
    public func previousFrame() -> MImage? {
        guard let tex = renderer.previousFrameTexture else { return nil }
        return MImage(texture: tex)
    }

    // MARK: - Post Process

    /// カスタムポストプロセスエフェクトを作成
    ///
    /// MSLフラグメントシェーダーソースからカスタムエフェクトを作成する。
    /// シェーダーには `PostProcessShaders.commonStructs` をプリフィックスとして含めること。
    /// - Parameters:
    ///   - name: エフェクト名（ライブラリキーに使用）
    ///   - source: MSLシェーダーソースコード
    ///   - fragmentFunction: フラグメントシェーダー関数名
    /// - Returns: CustomPostEffect インスタンス
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        let key = "user.posteffect.\(name)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard renderer.shaderLibrary.function(named: fragmentFunction, from: key) != nil else {
            throw PostProcessError.shaderNotFound(fragmentFunction)
        }
        return CustomPostEffect(name: name, fragmentFunctionName: fragmentFunction, libraryKey: key)
    }

    /// ポストプロセスエフェクトを追加
    public func addPostEffect(_ effect: PostEffect) {
        renderer.addPostEffect(effect)
    }

    /// ポストプロセスエフェクトを削除
    public func removePostEffect(at index: Int) {
        renderer.removePostEffect(at: index)
    }

    /// 全ポストプロセスエフェクトを削除
    public func clearPostEffects() {
        renderer.clearPostEffects()
    }

    /// ポストプロセスエフェクトを一括設定
    public func setPostEffects(_ effects: [PostEffect]) {
        renderer.setPostEffects(effects)
    }

    // MARK: - Unified Transform Stack

    /// 2D/3Dトランスフォームとスタイルを保存
    public func push() {
        canvas.push()
        canvas3D.pushState()
    }

    /// 2D/3Dトランスフォームとスタイルを復元
    public func pop() {
        canvas.pop()
        canvas3D.popState()
    }

    /// スタイル状態のみを保存（2D）
    public func pushStyle() {
        canvas.pushStyle()
    }

    /// スタイル状態のみを復元（2D）
    public func popStyle() {
        canvas.popStyle()
    }

    /// 2D平行移動
    public func translate(_ x: Float, _ y: Float) {
        canvas.translate(x, y)
    }

    /// 2D回転（ラジアン）
    public func rotate(_ angle: Float) {
        canvas.rotate(angle)
    }

    /// 2Dスケール
    public func scale(_ sx: Float, _ sy: Float) {
        canvas.scale(sx, sy)
    }

    /// 均一スケール（Canvas2D / Canvas3D 両方に適用）
    public func scale(_ s: Float) {
        canvas.scale(s)
        canvas3D.scale(s, s, s)
    }

    // MARK: - 2D Shapes

    /// 矩形
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.rect(x, y, w, h)
    }

    /// 角丸矩形（均一コーナー半径）
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        canvas.rect(x, y, w, h, r)
    }

    /// 角丸矩形（コーナー別半径）
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        canvas.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// 線形グラデーション矩形を描画
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        canvas.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// 放射状グラデーションを描画
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        canvas.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// 楕円
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.ellipse(x, y, w, h)
    }

    /// 円
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        canvas.circle(x, y, diameter)
    }

    /// 正方形
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        canvas.square(x, y, size)
    }

    /// 四辺形
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// 直線
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        canvas.line(x1, y1, x2, y2)
    }

    /// 三角形
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        canvas.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// 多角形
    public func polygon(_ points: [(Float, Float)]) {
        canvas.polygon(points)
    }

    /// 多角形（Vec2配列版）
    public func polygon(_ points: [Vec2]) {
        canvas.polygon(points.map { ($0.x, $0.y) })
    }

    /// 円弧
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        canvas.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// 3次ベジェ曲線
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// 点
    public func point(_ x: Float, _ y: Float) {
        canvas.point(x, y)
    }

    // MARK: - Custom Shapes (beginShape / endShape)

    /// 頂点ベースの形状記録を開始
    public func beginShape(_ mode: ShapeMode = .polygon) {
        canvas.beginShape(mode)
    }

    /// 形状に頂点を追加
    public func vertex(_ x: Float, _ y: Float) {
        canvas.vertex(x, y)
    }

    /// ベジェ曲線の制御点と終点を追加
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Catmull-Romスプラインの頂点を追加
    public func curveVertex(_ x: Float, _ y: Float) {
        canvas.curveVertex(x, y)
    }

    /// カーブの分割数を設定
    public func curveDetail(_ n: Int) {
        canvas.curveDetail(n)
    }

    /// カーブの張り具合を設定
    public func curveTightness(_ t: Float) {
        canvas.curveTightness(t)
    }

    /// コンター（穴）の記録を開始
    public func beginContour() {
        canvas.beginContour()
    }

    /// コンター（穴）の記録を終了
    public func endContour() {
        canvas.endContour()
    }

    /// 頂点カラー付きで頂点を追加（2D）
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        canvas.vertex(x, y, color)
    }

    /// UV座標付きで頂点を追加（2D）
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        canvas.vertex(x, y, u, v)
    }

    /// 形状記録を終了して描画
    public func endShape(_ close: CloseMode = .open) {
        canvas.endShape(close)
    }

    // MARK: - 3D Custom Shapes (beginShape / endShape)

    /// 3D頂点ベースの形状記録を開始
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        canvas3D.beginShape(mode)
    }

    /// 3D頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.vertex(x, y, z)
    }

    /// 頂点カラー付き3D頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        canvas3D.vertex(x, y, z, color)
    }

    /// 次の3D vertex に適用する法線を設定
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        canvas3D.normal(nx, ny, nz)
    }

    /// 3D形状記録を終了して描画
    public func endShape3D(_ close: CloseMode = .open) {
        canvas3D.endShape(close)
    }

    /// Catmull-Romスプライン曲線
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    // MARK: - 3D Camera

    /// カメラ位置を設定
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        canvas3D.camera(eye: eye, center: center, up: up)
    }

    /// カメラ位置を設定（位置引数版、p5.js風）
    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        canvas3D.camera(
            eye: SIMD3(eyeX, eyeY, eyeZ),
            center: SIMD3(centerX, centerY, centerZ),
            up: SIMD3(upX, upY, upZ)
        )
    }

    /// 透視投影を設定
    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        canvas3D.perspective(fov: fov, near: near, far: far)
    }

    /// 正射影カメラに切り替え
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: - 3D Lighting

    /// デフォルトライティングを有効化
    public func lights() {
        canvas3D.lights()
    }

    /// 全ライトを除去
    public func noLights() {
        canvas3D.noLights()
    }

    /// 平行光源の方向を設定
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    /// 平行光源の方向と色を設定
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    /// ポイントライトを追加
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// スポットライトを追加
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// アンビエント光の強さを設定
    public func ambientLight(_ strength: Float) {
        canvas3D.ambientLight(strength)
    }

    /// アンビエント光をRGBで設定
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        canvas3D.ambientLight(r, g, b)
    }

    // MARK: - Shadow Mapping

    /// シャドウマッピングを有効にする
    /// - Parameter resolution: シャドウマップ解像度（デフォルト 2048）
    public func enableShadows(resolution: Int = 2048) {
        if canvas3D.shadowMap == nil {
            canvas3D.shadowMap = try? ShadowMap(
                device: renderer.device,
                shaderLibrary: renderer.shaderLibrary,
                resolution: resolution
            )
        }
    }

    /// シャドウマッピングを無効にする
    public func disableShadows() {
        canvas3D.shadowMap = nil
    }

    /// シャドウバイアスを設定（アクネ防止）
    public func shadowBias(_ value: Float) {
        canvas3D.shadowMap?.shadowBias = value
    }

    // MARK: - 3D Material

    /// スペキュラ色を設定
    public func specular(_ color: Color) {
        canvas3D.specular(color)
    }

    /// スペキュラ色をグレースケールで設定
    public func specular(_ gray: Float) {
        canvas3D.specular(gray)
    }

    /// シャイネスを設定
    public func shininess(_ value: Float) {
        canvas3D.shininess(value)
    }

    /// エミッシブ色を設定
    public func emissive(_ color: Color) {
        canvas3D.emissive(color)
    }

    /// エミッシブ色をグレースケールで設定
    public func emissive(_ gray: Float) {
        canvas3D.emissive(gray)
    }

    /// メタリック係数を設定
    public func metallic(_ value: Float) {
        canvas3D.metallic(value)
    }

    /// PBR roughness を設定（自動的に PBR モードに切り替わる）
    /// - Parameter value: 0.0（鏡面）〜 1.0（完全拡散）
    public func roughness(_ value: Float) {
        canvas3D.roughness(value)
    }

    /// PBR アンビエントオクルージョンを設定
    /// - Parameter value: 0.0（完全遮蔽）〜 1.0（遮蔽なし）
    public func ambientOcclusion(_ value: Float) {
        canvas3D.ambientOcclusion(value)
    }

    /// PBR モードを明示的に切り替える
    /// - Parameter enabled: true で PBR（Cook-Torrance GGX）、false で Blinn-Phong
    public func pbr(_ enabled: Bool) {
        canvas3D.pbr(enabled)
    }

    // MARK: - 3D Custom Material

    /// カスタムフラグメントシェーダーマテリアルを作成
    ///
    /// MSLソースをコンパイルし、指定したフラグメント関数からCustomMaterialを生成する。
    /// ソースには `BuiltinShaders.canvas3DStructs` をプレフィックスとして含めること。
    /// - Parameters:
    ///   - source: MSLシェーダーソースコード
    ///   - fragmentFunction: フラグメントシェーダー関数名
    /// - Returns: CustomMaterial インスタンス
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.register(source: source, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw CustomMaterialError.shaderNotFound(fragmentFunction)
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw CustomMaterialError.shaderNotFound(vtxName)
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    /// カスタムマテリアルを適用
    public func material(_ customMaterial: CustomMaterial) {
        canvas3D.material(customMaterial)
    }

    /// カスタムマテリアルを解除（組み込みシェーダーに戻す）
    public func noMaterial() {
        canvas3D.noMaterial()
    }

    // MARK: - 3D Texture

    /// テクスチャを設定
    public func texture(_ img: MImage) {
        canvas3D.texture(img)
    }

    /// テクスチャを解除
    public func noTexture() {
        canvas3D.noTexture()
    }

    // MARK: - 3D Transform Stack

    /// 3Dトランスフォームのみを保存
    public func pushMatrix() {
        canvas.pushMatrix()
        canvas3D.pushMatrix()
    }

    /// 3Dトランスフォームのみを復元
    public func popMatrix() {
        canvas.popMatrix()
        canvas3D.popMatrix()
    }

    /// 3D平行移動
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.translate(x, y, z)
    }

    /// X軸回転
    public func rotateX(_ angle: Float) {
        canvas3D.rotateX(angle)
    }

    /// Y軸回転
    public func rotateY(_ angle: Float) {
        canvas3D.rotateY(angle)
    }

    /// Z軸回転
    public func rotateZ(_ angle: Float) {
        canvas3D.rotateZ(angle)
    }

    /// 3Dスケール
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.scale(x, y, z)
    }

    // MARK: - 3D Shapes

    /// ボックス
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        canvas3D.box(width, height, depth)
    }

    /// 均一ボックス
    public func box(_ size: Float) {
        canvas3D.box(size)
    }

    /// 球体
    public func sphere(_ radius: Float, detail: Int = 24) {
        canvas3D.sphere(radius, detail: detail)
    }

    /// 平面
    public func plane(_ width: Float, _ height: Float) {
        canvas3D.plane(width, height)
    }

    /// シリンダー
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cylinder(radius: radius, height: height, detail: detail)
    }

    /// コーン
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        canvas3D.cone(radius: radius, height: height, detail: detail)
    }

    /// トーラス
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    /// カスタムメッシュを描画
    public func mesh(_ mesh: Mesh) {
        canvas3D.mesh(mesh)
    }

    /// 動的メッシュを描画
    public func dynamicMesh(_ mesh: DynamicMesh) {
        canvas3D.dynamicMesh(mesh)
    }

    /// 動的メッシュを作成
    public func createDynamicMesh() -> DynamicMesh {
        DynamicMesh(device: renderer.device)
    }

    /// 3Dモデルファイルを読み込み（OBJ / USDZ / ABC 対応）
    /// - Parameters:
    ///   - path: ファイルパス
    ///   - normalize: true ならバウンディングボックスを [-1,1] に正規化（デフォルト true）
    public func loadModel(_ path: String, normalize: Bool = true) -> Mesh? {
        let url = URL(fileURLWithPath: path)
        return try? Mesh.load(device: renderer.device, url: url, normalize: normalize)
    }

    // MARK: - Compute

    /// コンピュートカーネルを作成
    /// - Parameters:
    ///   - source: MSLソースコード
    ///   - function: カーネル関数名
    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try ComputeKernel(device: renderer.device, source: source, functionName: function)
    }

    /// 型付きGPUバッファを作成（ゼロ初期化）
    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, count: count)
    }

    /// 配列からGPUバッファを作成
    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        GPUBuffer<T>(device: renderer.device, data: data)
    }

    /// 1Dコンピュートディスパッチ
    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: threads, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// 2Dコンピュートディスパッチ
    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        guard let encoder = ensureComputeEncoder() else { return }
        encoder.setComputePipelineState(kernel.pipelineState)
        configure(encoder)

        let w = kernel.threadExecutionWidth
        let h = max(1, kernel.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// コンピュートメモリバリア（ディスパッチ間のデータ依存解決用）
    public func computeBarrier() {
        _computeEncoder?.memoryBarrier(scope: .buffers)
    }

    /// コンピュートエンコーダを遅延作成
    private func ensureComputeEncoder() -> MTLComputeCommandEncoder? {
        if let existing = _computeEncoder { return existing }
        guard let cb = _commandBuffer else { return nil }
        let encoder = cb.makeComputeCommandEncoder()
        _computeEncoder = encoder
        return encoder
    }

    // MARK: - Particle System

    /// GPU パーティクルシステムを作成
    /// - Parameter count: パーティクル数（デフォルト100,000）
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try ParticleSystem(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            sampleCount: renderer.textureManager.sampleCount,
            count: count
        )
    }

    /// パーティクルシステムを更新（compute() 内で呼ぶ）
    public func updateParticles(_ system: ParticleSystem) {
        guard let encoder = ensureComputeEncoder() else { return }
        system.update(encoder: encoder, deltaTime: deltaTime, time: time)
    }

    /// パーティクルシステムを描画（draw() 内で呼ぶ）
    public func drawParticles(_ system: ParticleSystem) {
        canvas.flush()
        guard let enc = canvas.currentEncoder else { return }
        system.draw(
            encoder: enc,
            viewProjection: canvas3D.currentViewProjection,
            cameraRight: canvas3D.currentCameraRight,
            cameraUp: canvas3D.currentCameraUp
        )
    }

    // MARK: - Audio

    /// オーディオ入力アナライザーを作成
    /// - Parameter fftSize: FFT サイズ（デフォルト1024）
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        AudioAnalyzer(fftSize: fftSize)
    }

    // MARK: - OSC

    /// OSC レシーバーを作成
    /// - Parameter port: UDP ポート番号
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        OSCReceiver(port: port)
    }

    // MARK: - Shader Hot Reload

    /// シェーダーソースを再コンパイルしてパイプラインキャッシュをクリアする
    ///
    /// CustomMaterial / CustomPostEffect の reload() と組み合わせて使う。
    /// - Parameters:
    ///   - key: ShaderLibrary の登録キー
    ///   - source: 新しい MSL ソースコード
    public func reloadShader(key: String, source: String) throws {
        try renderer.shaderLibrary.reload(key: key, source: source)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// 外部ファイルからシェーダーを再読み込みしてパイプラインキャッシュをクリアする
    /// - Parameters:
    ///   - key: ShaderLibrary の登録キー
    ///   - path: MSL ファイルパス
    public func reloadShaderFromFile(key: String, path: String) throws {
        try renderer.shaderLibrary.reloadFromFile(key: key, path: path)
        canvas3D.clearCustomPipelineCache()
        renderer.postProcessPipeline?.invalidatePipelines()
    }

    /// 外部ファイルから MSL ソースを読み込んでマテリアルを作成する
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        let key = "user.material.\(fragmentFunction)"
        try renderer.shaderLibrary.registerFromFile(path: path, as: key)
        guard let fn = renderer.shaderLibrary.function(named: fragmentFunction, from: key) else {
            throw CustomMaterialError.shaderNotFound(fragmentFunction)
        }

        var vtxFn: MTLFunction? = nil
        if let vtxName = vertexFunction {
            guard let vf = renderer.shaderLibrary.function(named: vtxName, from: key) else {
                throw CustomMaterialError.shaderNotFound(vtxName)
            }
            vtxFn = vf
        }

        return CustomMaterial(
            fragmentFunction: fn, functionName: fragmentFunction, libraryKey: key,
            vertexFunction: vtxFn, vertexFunctionName: vertexFunction
        )
    }

    // MARK: - Tween

    /// Tween を作成し TweenManager に登録
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T> {
        let t = Tween(from: from, to: to, duration: duration, easing: easing)
        tweenManager.add(t)
        return t
    }

    // MARK: - Sound File (D-16)

    /// オーディオファイルを読み込む
    /// - Parameter path: ファイルパス
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }

    // MARK: - MIDI (D-17)

    /// MIDI マネージャーを作成
    public func createMIDI() -> MIDIManager {
        MIDIManager()
    }

    // MARK: - GIF Export (D-19)

    /// GIF エクスポーター
    public let gifExporter = GIFExporter()

    /// GIF 録画を開始
    /// - Parameter fps: フレームレート（デフォルト15）
    public func beginGIFRecord(fps: Int = 15) {
        gifExporter.beginRecord(
            fps: fps,
            width: renderer.textureManager.width,
            height: renderer.textureManager.height
        )
    }

    /// GIF フレームをキャプチャ（内部的に毎フレーム呼ばれる）
    func captureGIFFrame() {
        guard gifExporter.isRecording else { return }
        gifExporter.captureFrame(
            texture: renderer.textureManager.colorTexture,
            device: renderer.device
        )
    }

    /// GIF 録画を終了してファイルに書き出し
    /// - Parameter path: 出力ファイルパス（nilならデスクトップに自動生成）
    public func endGIFRecord(_ path: String? = nil) throws {
        let actualPath: String
        if let path {
            actualPath = path
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            actualPath = NSHomeDirectory() + "/Desktop/metaphor_\(formatter.string(from: Date())).gif"
        }
        try gifExporter.endRecord(to: actualPath)
    }

    // MARK: - Physics 2D

    /// 2D 物理ワールドを作成
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        Physics2D(cellSize: cellSize)
    }

    // MARK: - Orbit Camera (D-20)

    /// オービットカメラ
    public let orbitCamera = OrbitCamera()

    /// オービットコントロールを有効化（draw() 内で呼ぶ）
    /// マウスドラッグでカメラを回転、スクロールでズーム
    public func orbitControl() {
        let inp = input

        // マウスドラッグでカメラを回転
        if inp.isMouseDown {
            let dx = inp.mouseX - inp.pmouseX
            let dy = inp.mouseY - inp.pmouseY
            orbitCamera.handleMouseDrag(dx: dx, dy: dy)
        }

        // スクロールでズーム
        let sy = inp.scrollY
        if abs(sy) > 0.01 {
            orbitCamera.handleScroll(delta: sy)
        }

        // ダンピング更新
        orbitCamera.update()

        // Canvas3D に適用
        canvas3D.camera(eye: orbitCamera.eye, center: orbitCamera.target, up: orbitCamera.up)
    }

    // MARK: - Scene Graph

    /// ノードを作成
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// シーングラフを描画
    public func drawScene(_ root: Node) {
        SceneRenderer.render(node: root, canvas: canvas3D)
    }

    // MARK: - Render Graph

    /// ソースパスを作成
    /// - Parameters:
    ///   - label: ノードのラベル
    ///   - width: テクスチャの幅
    ///   - height: テクスチャの高さ
    /// - Returns: SourcePass（失敗時は nil）
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        try? SourcePass(
            label: label,
            device: renderer.device,
            width: width,
            height: height
        )
    }

    /// エフェクトパスを作成
    /// - Parameters:
    ///   - input: 入力パスノード
    ///   - effects: ポストプロセスエフェクト配列
    /// - Returns: EffectPass（失敗時は nil）
    public func createEffectPass(_ input: RenderPassNode, effects: [PostEffect]) -> EffectPass? {
        try? EffectPass(
            input,
            effects: effects,
            device: renderer.device,
            commandQueue: renderer.commandQueue,
            shaderLibrary: renderer.shaderLibrary
        )
    }

    /// マージパスを作成
    /// - Parameters:
    ///   - a: ベースパス
    ///   - b: オーバーレイパス
    ///   - blend: ブレンドモード
    /// - Returns: MergePass（失敗時は nil）
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
        try? MergePass(
            a, b,
            blend: blend,
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary
        )
    }

    /// レンダーグラフを設定
    /// - Parameter graph: RenderGraph（nil で解除）
    public func setRenderGraph(_ graph: RenderGraph?) {
        renderer.renderGraph = graph
    }

    // MARK: - CoreML / Vision

    /// CoreML モデルラッパーを作成
    public func createMLProcessor() -> MLProcessor {
        MLProcessor(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// Vision フレームワークラッパーを作成
    public func createVision() -> MLVision {
        MLVision(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// スタイル転送ラッパーを作成
    public func createStyleTransfer() -> MLStyleTransfer {
        MLStyleTransfer(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// CoreML モデルを読み込んで MLProcessor を返す
    public func loadMLModel(_ path: String, computeUnit: MLComputeUnit = .all) throws -> MLProcessor {
        let processor = createMLProcessor()
        processor.computeUnit = computeUnit
        try processor.load(path)
        return processor
    }

    /// バンドルリソースから CoreML モデルを読み込む
    public func loadMLModel(named name: String, computeUnit: MLComputeUnit = .all) throws -> MLProcessor {
        let processor = createMLProcessor()
        processor.computeUnit = computeUnit
        try processor.load(named: name)
        return processor
    }

    /// スタイル転送モデルを読み込む
    public func loadStyleTransfer(_ path: String, computeUnit: MLComputeUnit = .all) throws -> MLStyleTransfer {
        let st = createStyleTransfer()
        try st.load(path, computeUnit: computeUnit)
        return st
    }

    /// テクスチャコンバーター（上級者向け）
    public func createMLTextureConverter() -> MLTextureConverter {
        MLTextureConverter(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    // MARK: - GameplayKit Noise

    /// GameplayKit ノイズジェネレーターを作成
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig()) -> GKNoiseWrapper {
        GKNoiseWrapper(type: type, config: config, device: renderer.device)
    }

    /// ノイズテクスチャを生成（便利メソッド）
    public func noiseTexture(_ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()) -> MImage? {
        let noise = GKNoiseWrapper(type: type, config: config, device: renderer.device)
        return noise.image(width: width, height: height)
    }

    // MARK: - MPS Image Filter

    /// MPS 画像フィルタを作成
    public func createMPSFilter() -> MPSImageFilterWrapper {
        MPSImageFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
    }

    /// MPS レイトレーサーを作成
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try MPSRayTracer(device: renderer.device, commandQueue: renderer.commandQueue, width: width, height: height)
    }

    // MARK: - CoreImage Filter

    private var _ciFilterWrapper: CIFilterWrapper?

    private func ensureCIFilterWrapper() -> CIFilterWrapper {
        if let wrapper = _ciFilterWrapper { return wrapper }
        let wrapper = CIFilterWrapper(device: renderer.device, commandQueue: renderer.commandQueue)
        _ciFilterWrapper = wrapper
        return wrapper
    }

    /// CoreImage フィルタを MImage に適用（プリセット）
    public func ciFilter(_ image: MImage, _ preset: CIFilterPreset) {
        ensureCIFilterWrapper().apply(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(
                width: CGFloat(image.width), height: CGFloat(image.height)
            )),
            to: image
        )
    }

    /// CoreImage フィルタを MImage に適用（フィルタ名直接指定）
    public func ciFilter(_ image: MImage, name: String, parameters: [String: Any] = [:]) {
        ensureCIFilterWrapper().apply(filterName: name, parameters: parameters, to: image)
    }

    /// CoreImage ジェネレーターフィルタで画像を生成
    public func ciGenerate(_ preset: CIFilterPreset, width: Int, height: Int) -> MImage? {
        guard let tex = ensureCIFilterWrapper().generate(
            filterName: preset.filterName,
            parameters: preset.parameters(textureSize: CGSize(width: width, height: height)),
            width: width,
            height: height
        ) else { return nil }
        return MImage(texture: tex)
    }
}
