import AppKit
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
        canvas3D.begin(encoder: encoder, time: time)
        canvas.begin(encoder: encoder, bufferIndex: renderer.frameBufferIndex)
    }

    func endFrame() {
        canvas3D.end()
        canvas.end()
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

    // MARK: - Color Mode

    /// 色空間と最大値を設定
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        canvas.colorMode(space, max1, max2, max3, maxA)
    }

    /// 色空間と均一な最大値を設定
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        canvas.colorMode(space, maxAll)
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
    }

    /// グレースケールで塗りつぶし色を設定
    public func fill(_ gray: Float) {
        canvas.fill(gray)
    }

    /// グレースケール＋アルファで塗りつぶし色を設定
    public func fill(_ gray: Float, _ alpha: Float) {
        canvas.fill(gray, alpha)
    }

    /// 塗りつぶしなし（2Dのみ）
    public func noFill() {
        canvas.noFill()
    }

    /// 線の色を設定（2Dのみ）
    public func stroke(_ color: Color) {
        canvas.stroke(color)
    }

    /// 線の色を設定（colorModeに従って解釈、2Dのみ）
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        canvas.stroke(v1, v2, v3, a)
    }

    /// グレースケールで線の色を設定
    public func stroke(_ gray: Float) {
        canvas.stroke(gray)
    }

    /// グレースケール＋アルファで線の色を設定
    public func stroke(_ gray: Float, _ alpha: Float) {
        canvas.stroke(gray, alpha)
    }

    /// 線なし（2Dのみ）
    public func noStroke() {
        canvas.noStroke()
    }

    /// 線の太さを設定（2Dのみ）
    public func strokeWeight(_ weight: Float) {
        canvas.strokeWeight(weight)
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

    /// 画像をサイズ指定で描画
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.image(img, x, y, w, h)
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

    /// テキストの描画幅を取得
    public func textWidth(_ string: String) -> Float {
        canvas.textWidth(string)
    }

    /// テキストを描画
    public func text(_ string: String, _ x: Float, _ y: Float) {
        canvas.text(string, x, y)
    }

    // MARK: - Screenshot

    /// スクリーンショットを保存
    public func save(_ path: String) {
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

    // MARK: - Post Process

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

    // MARK: - 2D Transform Stack

    /// 2Dトランスフォームとスタイルを保存
    public func push() {
        canvas.push()
    }

    /// 2Dトランスフォームとスタイルを復元
    public func pop() {
        canvas.pop()
    }

    /// スタイル状態のみを保存
    public func pushStyle() {
        canvas.pushStyle()
    }

    /// スタイル状態のみを復元
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

    /// 2D均一スケール
    public func scale(_ s: Float) {
        canvas.scale(s)
    }

    // MARK: - 2D Shapes

    /// 矩形
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.rect(x, y, w, h)
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

    /// 形状記録を終了して描画
    public func endShape(_ close: CloseMode = .open) {
        canvas.endShape(close)
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

    /// 3Dトランスフォームを保存
    public func pushMatrix() {
        canvas3D.pushMatrix()
    }

    /// 3Dトランスフォームを復元
    public func popMatrix() {
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
}
