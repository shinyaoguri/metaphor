#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@preconcurrency import Metal

/// p5.js風のスケッチプロトコル
///
/// `@main` を付けたclassで実装するだけで、ウィンドウ・レンダラー・Canvas2Dが
/// 自動的にセットアップされ、`draw()` が毎フレーム呼ばれる。
///
/// ```swift
/// // スタイルA: コンテキスト引数あり
/// @main
/// final class MySketch: Sketch {
///     func draw(_ ctx: SketchContext) {
///         ctx.background(.black)
///         ctx.fill(.white)
///         ctx.circle(ctx.width / 2, ctx.height / 2, 200)
///     }
/// }
///
/// // スタイルB: 引数なし（ctx.省略可）
/// @main
/// final class MySketch: Sketch {
///     func draw() {
///         background(.black)
///         fill(.white)
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```
@MainActor
public protocol Sketch: AnyObject {
    /// 引数なしイニシャライザ（`@main` に必要）
    init()

    /// スケッチの設定（省略可）
    var config: SketchConfig { get }

    /// 初期化時に一度呼ばれる（省略可）
    func setup()

    /// 毎フレーム呼ばれる（どちらか一方を実装）
    func draw(_ ctx: SketchContext)

    /// 毎フレーム呼ばれる（ctx省略版。描画メソッドを直接呼べる）
    func draw()

    /// 毎フレーム draw() の前に呼ばれるGPUコンピュートフェーズ（省略可）
    func compute()

    // MARK: - Input Events（全て省略可）

    /// マウスボタンが押された
    func mousePressed()

    /// マウスボタンが離された
    func mouseReleased()

    /// マウスが移動した
    func mouseMoved()

    /// マウスがドラッグされた
    func mouseDragged()

    /// マウスホイールがスクロールされた
    func mouseScrolled()

    /// キーが押された
    func keyPressed()

    /// キーが離された
    func keyReleased()
}

// MARK: - Active Context (internal global)

/// SketchRunnerが設定するアクティブなコンテキスト
///
/// スレッド安全性: `@MainActor` によりメインスレッドからのみアクセス可能。
/// Processing / p5.js / openFrameworks と同様、単一コンテキストモデルを採用。
/// 同時に複数の Sketch インスタンスを実行することはサポートしない。
@MainActor
var _activeSketchContext: SketchContext?

// MARK: - Active Context Helper

extension Sketch {
    /// アクティブなコンテキストを取得（setup/draw 外からの呼び出し時は fatalError）
    @MainActor
    fileprivate func activeContext(function: String = #function) -> SketchContext {
        guard let ctx = _activeSketchContext else {
            fatalError("[\(function)] must be called inside setup() or draw()")
        }
        return ctx
    }
}

// MARK: - Default Implementations

extension Sketch {
    public var config: SketchConfig { SketchConfig() }
    public func setup() {}
    public func draw(_ ctx: SketchContext) { draw() }
    public func draw() {}
    public func compute() {}
    public func mousePressed() {}
    public func mouseReleased() {}
    public func mouseMoved() {}
    public func mouseDragged() {}
    public func mouseScrolled() {}
    public func keyPressed() {}
    public func keyReleased() {}
}

// MARK: - Convenience Properties

extension Sketch {
    /// キャンバスの幅（ピクセル）
    public var width: Float {
        _activeSketchContext?.width ?? 0
    }

    /// キャンバスの高さ（ピクセル）
    public var height: Float {
        _activeSketchContext?.height ?? 0
    }

    /// 入力マネージャ（イベントハンドラ内で使用）
    public var input: InputManager {
        activeContext().input
    }

    /// マウスX座標
    public var mouseX: Float {
        _activeSketchContext?.input.mouseX ?? 0
    }

    /// マウスY座標
    public var mouseY: Float {
        _activeSketchContext?.input.mouseY ?? 0
    }

    /// 前フレームのマウスX座標
    public var pmouseX: Float {
        _activeSketchContext?.input.pmouseX ?? 0
    }

    /// 前フレームのマウスY座標
    public var pmouseY: Float {
        _activeSketchContext?.input.pmouseY ?? 0
    }

    /// マウスボタンが押されているか
    public var isMousePressed: Bool {
        _activeSketchContext?.input.isMouseDown ?? false
    }

    /// 現フレームのスクロールX量
    public var scrollX: Float {
        _activeSketchContext?.input.scrollX ?? 0
    }

    /// 現フレームのスクロールY量
    public var scrollY: Float {
        _activeSketchContext?.input.scrollY ?? 0
    }

    /// 押されているマウスボタン (0=左, 1=右, 2=中)
    public var mouseButton: Int {
        _activeSketchContext?.input.mouseButton ?? 0
    }

    /// キーが押されているか
    public var isKeyPressed: Bool {
        _activeSketchContext?.input.isKeyPressed ?? false
    }

    /// 最後に押されたキー
    public var key: Character? {
        _activeSketchContext?.input.lastKey
    }

    /// 最後に押されたキーコード
    public var keyCode: UInt16? {
        _activeSketchContext?.input.lastKeyCode
    }

    /// 経過時間（秒）
    public var time: Float {
        _activeSketchContext?.time ?? 0
    }

    /// フレーム間の時間（秒）
    public var deltaTime: Float {
        _activeSketchContext?.deltaTime ?? 0
    }

    /// フレーム番号
    public var frameCount: Int {
        _activeSketchContext?.frameCount ?? 0
    }
}

// MARK: - Canvas Setup

extension Sketch {
    /// キャンバスサイズを設定（setup()内で呼ぶ、p5.js風）
    public func createCanvas(width: Int, height: Int) {
        _activeSketchContext?.createCanvas(width: width, height: height)
    }
}

// MARK: - Vector Factory

extension Sketch {
    /// 2Dベクトルを作成（Processing PVector互換）
    public func createVector(_ x: Float = 0, _ y: Float = 0) -> Vec2 {
        Vec2(x, y)
    }

    /// 3Dベクトルを作成（Processing PVector互換）
    public func createVector(_ x: Float, _ y: Float, _ z: Float) -> Vec3 {
        Vec3(x, y, z)
    }
}

// MARK: - Animation Control

extension Sketch {
    /// アニメーションループ中かどうか
    public var isLooping: Bool {
        _activeSketchContext?.isLooping ?? true
    }

    /// アニメーションを再開
    public func loop() {
        _activeSketchContext?.loop()
    }

    /// アニメーションを停止
    public func noLoop() {
        _activeSketchContext?.noLoop()
    }

    /// 1フレームだけ描画（noLoop時に使用）
    public func redraw() {
        _activeSketchContext?.redraw()
    }

    /// フレームレートを動的に変更
    public func frameRate(_ fps: Int) {
        _activeSketchContext?.frameRate(fps)
    }
}

// MARK: - Drawing Methods (ctx省略用)

extension Sketch {

    // MARK: Shape Mode Settings

    public func rectMode(_ mode: RectMode) {
        _activeSketchContext?.rectMode(mode)
    }

    public func ellipseMode(_ mode: EllipseMode) {
        _activeSketchContext?.ellipseMode(mode)
    }

    public func imageMode(_ mode: ImageMode) {
        _activeSketchContext?.imageMode(mode)
    }

    // MARK: Color Mode

    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        _activeSketchContext?.colorMode(space, max1, max2, max3, maxA)
    }

    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        _activeSketchContext?.colorMode(space, maxAll)
    }

    // MARK: Background

    public func background(_ color: Color) {
        _activeSketchContext?.background(color)
    }

    public func background(_ gray: Float) {
        _activeSketchContext?.background(gray)
    }

    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.background(v1, v2, v3, a)
    }

    // MARK: Style

    public func fill(_ color: Color) {
        _activeSketchContext?.fill(color)
    }

    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.fill(v1, v2, v3, a)
    }

    public func fill(_ gray: Float) {
        _activeSketchContext?.fill(gray)
    }

    public func fill(_ gray: Float, _ alpha: Float) {
        _activeSketchContext?.fill(gray, alpha)
    }

    public func noFill() {
        _activeSketchContext?.noFill()
    }

    public func stroke(_ color: Color) {
        _activeSketchContext?.stroke(color)
    }

    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.stroke(v1, v2, v3, a)
    }

    public func stroke(_ gray: Float) {
        _activeSketchContext?.stroke(gray)
    }

    public func stroke(_ gray: Float, _ alpha: Float) {
        _activeSketchContext?.stroke(gray, alpha)
    }

    public func noStroke() {
        _activeSketchContext?.noStroke()
    }

    public func strokeWeight(_ weight: Float) {
        _activeSketchContext?.strokeWeight(weight)
    }

    public func strokeCap(_ cap: StrokeCap) {
        _activeSketchContext?.strokeCap(cap)
    }

    public func strokeJoin(_ join: StrokeJoin) {
        _activeSketchContext?.strokeJoin(join)
    }

    public func blendMode(_ mode: BlendMode) {
        _activeSketchContext?.blendMode(mode)
    }

    // MARK: Tint

    public func tint(_ color: Color) {
        _activeSketchContext?.tint(color)
    }

    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        _activeSketchContext?.tint(v1, v2, v3, a)
    }

    public func tint(_ gray: Float) {
        _activeSketchContext?.tint(gray)
    }

    public func tint(_ gray: Float, _ alpha: Float) {
        _activeSketchContext?.tint(gray, alpha)
    }

    public func noTint() {
        _activeSketchContext?.noTint()
    }

    // MARK: Image

    public func loadImage(_ path: String) throws -> MImage {
        try activeContext().loadImage(path)
    }

    public func createImage(_ width: Int, _ height: Int) -> MImage? {
        _activeSketchContext?.createImage(width, height)
    }

    public func createGraphics(_ w: Int, _ h: Int) -> Graphics? {
        _activeSketchContext?.createGraphics(w, h)
    }

    public func createGraphics3D(_ w: Int, _ h: Int) -> Graphics3D? {
        _activeSketchContext?.createGraphics3D(w, h)
    }

    /// カメラキャプチャデバイスを作成
    public func createCapture(width: Int = 1280, height: Int = 720, position: CameraPosition = .front) -> CaptureDevice? {
        _activeSketchContext?.createCapture(width: width, height: height, position: position)
    }

    /// CaptureDeviceの最新フレームを描画
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(capture, x, y)
    }

    /// CaptureDeviceの最新フレームをサイズ指定で描画
    public func image(_ capture: CaptureDevice, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(capture, x, y, w, h)
    }

    public func image(_ pg: Graphics, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(pg, x, y)
    }

    public func image(_ pg: Graphics, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(pg, x, y, w, h)
    }

    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(pg, x, y)
    }

    public func image(_ pg: Graphics3D, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(pg, x, y, w, h)
    }

    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(img, x, y)
    }

    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(img, x, y, w, h)
    }

    /// サブイメージ描画（スプライトシート/タイルマップ用）
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        _activeSketchContext?.image(img, dx, dy, dw, dh, sx, sy, sw, sh)
    }

    // MARK: Text

    public func textSize(_ size: Float) {
        _activeSketchContext?.textSize(size)
    }

    public func textFont(_ family: String) {
        _activeSketchContext?.textFont(family)
    }

    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        _activeSketchContext?.textAlign(horizontal, vertical)
    }

    public func textLeading(_ leading: Float) {
        _activeSketchContext?.textLeading(leading)
    }

    public func text(_ string: String, _ x: Float, _ y: Float) {
        _activeSketchContext?.text(string, x, y)
    }

    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.text(string, x, y, w, h)
    }

    public func textWidth(_ string: String) -> Float {
        _activeSketchContext?.textWidth(string) ?? 0
    }

    public func textAscent() -> Float {
        _activeSketchContext?.textAscent() ?? 0
    }

    public func textDescent() -> Float {
        _activeSketchContext?.textDescent() ?? 0
    }

    // MARK: Screenshot & Recording

    public func save(_ path: String) {
        _activeSketchContext?.save(path)
    }

    public func save() {
        _activeSketchContext?.save()
    }

    public func beginRecord(directory: String? = nil, pattern: String = "frame_%05d.png") {
        _activeSketchContext?.beginRecord(directory: directory, pattern: pattern)
    }

    public func endRecord() {
        _activeSketchContext?.endRecord()
    }

    public func saveFrame(_ filename: String? = nil) {
        _activeSketchContext?.saveFrame(filename)
    }

    // MARK: Video Recording

    /// ビデオ録画を開始
    public func beginVideoRecord(_ path: String? = nil, config: VideoExportConfig = VideoExportConfig()) {
        _activeSketchContext?.beginVideoRecord(path, config: config)
    }

    /// ビデオ録画を終了
    public func endVideoRecord(completion: (@Sendable () -> Void)? = nil) {
        _activeSketchContext?.endVideoRecord(completion: completion)
    }

    // MARK: Offline Rendering

    /// オフラインレンダリングモードかどうか
    public var isOfflineRendering: Bool {
        _activeSketchContext?.isOfflineRendering ?? false
    }

    /// オフラインレンダリングモードを開始（決定論的タイミング）
    public func beginOfflineRender(fps: Double = 60) {
        _activeSketchContext?.beginOfflineRender(fps: fps)
    }

    /// オフラインレンダリングモードを終了
    public func endOfflineRender() {
        _activeSketchContext?.endOfflineRender()
    }

    // MARK: FBO Feedback

    /// フレームバッファフィードバックを有効化
    public func enableFeedback() {
        _activeSketchContext?.enableFeedback()
    }

    /// フレームバッファフィードバックを無効化
    public func disableFeedback() {
        _activeSketchContext?.disableFeedback()
    }

    /// 前フレームのレンダリング結果を取得
    public func previousFrame() -> MImage? {
        _activeSketchContext?.previousFrame()
    }

    // MARK: 2D Transform Stack

    public func push() {
        _activeSketchContext?.push()
    }

    public func pop() {
        _activeSketchContext?.pop()
    }

    public func pushStyle() {
        _activeSketchContext?.pushStyle()
    }

    public func popStyle() {
        _activeSketchContext?.popStyle()
    }

    public func translate(_ x: Float, _ y: Float) {
        _activeSketchContext?.translate(x, y)
    }

    public func rotate(_ angle: Float) {
        _activeSketchContext?.rotate(angle)
    }

    public func scale(_ sx: Float, _ sy: Float) {
        _activeSketchContext?.scale(sx, sy)
    }

    public func scale(_ s: Float) {
        _activeSketchContext?.scale(s)
    }

    // MARK: 2D Shapes

    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.rect(x, y, w, h)
    }

    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        _activeSketchContext?.rect(x, y, w, h, r)
    }

    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        _activeSketchContext?.rect(x, y, w, h, tl, tr, br, bl)
    }

    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        _activeSketchContext?.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        _activeSketchContext?.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.ellipse(x, y, w, h)
    }

    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        _activeSketchContext?.circle(x, y, diameter)
    }

    public func square(_ x: Float, _ y: Float, _ size: Float) {
        _activeSketchContext?.square(x, y, size)
    }

    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        _activeSketchContext?.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        _activeSketchContext?.line(x1, y1, x2, y2)
    }

    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        _activeSketchContext?.triangle(x1, y1, x2, y2, x3, y3)
    }

    public func polygon(_ points: [(Float, Float)]) {
        _activeSketchContext?.polygon(points)
    }

    /// 多角形（Vec2配列版）
    public func polygon(_ points: [Vec2]) {
        _activeSketchContext?.polygon(points)
    }

    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        _activeSketchContext?.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        _activeSketchContext?.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    public func point(_ x: Float, _ y: Float) {
        _activeSketchContext?.point(x, y)
    }

    // MARK: Custom Shapes (beginShape / endShape)

    public func beginShape(_ mode: ShapeMode = .polygon) {
        _activeSketchContext?.beginShape(mode)
    }

    public func vertex(_ x: Float, _ y: Float) {
        _activeSketchContext?.vertex(x, y)
    }

    /// 頂点カラー付きで頂点を追加（2D）
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        _activeSketchContext?.vertex(x, y, color)
    }

    /// UV座標付きで頂点を追加（2D）
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        _activeSketchContext?.vertex(x, y, u, v)
    }

    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        _activeSketchContext?.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    public func curveVertex(_ x: Float, _ y: Float) {
        _activeSketchContext?.curveVertex(x, y)
    }

    public func curveDetail(_ n: Int) {
        _activeSketchContext?.curveDetail(n)
    }

    public func curveTightness(_ t: Float) {
        _activeSketchContext?.curveTightness(t)
    }

    public func beginContour() {
        _activeSketchContext?.beginContour()
    }

    public func endContour() {
        _activeSketchContext?.endContour()
    }

    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        _activeSketchContext?.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    public func endShape(_ close: CloseMode = .open) {
        _activeSketchContext?.endShape(close)
    }

    // MARK: 3D Custom Shapes

    /// 3D頂点ベースの形状記録を開始
    public func beginShape3D(_ mode: ShapeMode = .polygon) {
        _activeSketchContext?.beginShape3D(mode)
    }

    /// 3D頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.vertex(x, y, z)
    }

    /// 頂点カラー付き3D頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        _activeSketchContext?.vertex(x, y, z, color)
    }

    /// 次の3D vertex に適用する法線を設定
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        _activeSketchContext?.normal(nx, ny, nz)
    }

    /// 3D形状記録を終了して描画
    public func endShape3D(_ close: CloseMode = .open) {
        _activeSketchContext?.endShape3D(close)
    }

    // MARK: 3D Camera

    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        _activeSketchContext?.camera(eye: eye, center: center, up: up)
    }

    public func camera(
        _ eyeX: Float, _ eyeY: Float, _ eyeZ: Float,
        _ centerX: Float, _ centerY: Float, _ centerZ: Float,
        _ upX: Float, _ upY: Float, _ upZ: Float
    ) {
        _activeSketchContext?.camera(eyeX, eyeY, eyeZ, centerX, centerY, centerZ, upX, upY, upZ)
    }

    public func perspective(fov: Float = Float.pi / 3, near: Float = 0.1, far: Float = 10000) {
        _activeSketchContext?.perspective(fov: fov, near: near, far: far)
    }

    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        _activeSketchContext?.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
    }

    // MARK: 3D Lighting

    public func lights() {
        _activeSketchContext?.lights()
    }

    public func noLights() {
        _activeSketchContext?.noLights()
    }

    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.directionalLight(x, y, z)
    }

    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        _activeSketchContext?.directionalLight(x, y, z, color: color)
    }

    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        _activeSketchContext?.pointLight(x, y, z, color: color, falloff: falloff)
    }

    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        _activeSketchContext?.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    public func ambientLight(_ strength: Float) {
        _activeSketchContext?.ambientLight(strength)
    }

    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        _activeSketchContext?.ambientLight(r, g, b)
    }

    // MARK: Shadow Mapping

    /// シャドウマッピングを有効にする
    public func enableShadows(resolution: Int = 2048) {
        _activeSketchContext?.enableShadows(resolution: resolution)
    }

    /// シャドウマッピングを無効にする
    public func disableShadows() {
        _activeSketchContext?.disableShadows()
    }

    /// シャドウバイアスを設定
    public func shadowBias(_ value: Float) {
        _activeSketchContext?.shadowBias(value)
    }

    // MARK: 3D Material

    public func specular(_ color: Color) {
        _activeSketchContext?.specular(color)
    }

    public func specular(_ gray: Float) {
        _activeSketchContext?.specular(gray)
    }

    public func shininess(_ value: Float) {
        _activeSketchContext?.shininess(value)
    }

    public func emissive(_ color: Color) {
        _activeSketchContext?.emissive(color)
    }

    public func emissive(_ gray: Float) {
        _activeSketchContext?.emissive(gray)
    }

    public func metallic(_ value: Float) {
        _activeSketchContext?.metallic(value)
    }

    /// PBR roughness を設定（自動的に PBR モードに切り替わる）
    public func roughness(_ value: Float) {
        _activeSketchContext?.roughness(value)
    }

    /// PBR アンビエントオクルージョンを設定
    public func ambientOcclusion(_ value: Float) {
        _activeSketchContext?.ambientOcclusion(value)
    }

    /// PBR モードを明示的に切り替える
    public func pbr(_ enabled: Bool) {
        _activeSketchContext?.pbr(enabled)
    }

    // MARK: 3D Custom Material

    /// カスタムシェーダーマテリアルを作成
    public func createMaterial(source: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try activeContext().createMaterial(source: source, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }

    /// カスタムマテリアルを適用
    public func material(_ customMaterial: CustomMaterial) {
        _activeSketchContext?.material(customMaterial)
    }

    /// カスタムマテリアルを解除
    public func noMaterial() {
        _activeSketchContext?.noMaterial()
    }

    // MARK: 3D Texture

    public func texture(_ img: MImage) {
        _activeSketchContext?.texture(img)
    }

    public func noTexture() {
        _activeSketchContext?.noTexture()
    }

    // MARK: 3D Transform Stack

    public func pushMatrix() {
        _activeSketchContext?.pushMatrix()
    }

    public func popMatrix() {
        _activeSketchContext?.popMatrix()
    }

    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.translate(x, y, z)
    }

    public func rotateX(_ angle: Float) {
        _activeSketchContext?.rotateX(angle)
    }

    public func rotateY(_ angle: Float) {
        _activeSketchContext?.rotateY(angle)
    }

    public func rotateZ(_ angle: Float) {
        _activeSketchContext?.rotateZ(angle)
    }

    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        _activeSketchContext?.scale(x, y, z)
    }

    // MARK: 3D Shapes

    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        _activeSketchContext?.box(width, height, depth)
    }

    public func box(_ size: Float) {
        _activeSketchContext?.box(size)
    }

    public func sphere(_ radius: Float, detail: Int = 24) {
        _activeSketchContext?.sphere(radius, detail: detail)
    }

    public func plane(_ width: Float, _ height: Float) {
        _activeSketchContext?.plane(width, height)
    }

    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        _activeSketchContext?.cylinder(radius: radius, height: height, detail: detail)
    }

    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        _activeSketchContext?.cone(radius: radius, height: height, detail: detail)
    }

    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        _activeSketchContext?.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail)
    }

    public func mesh(_ mesh: Mesh) {
        _activeSketchContext?.mesh(mesh)
    }

    /// 動的メッシュを描画
    public func dynamicMesh(_ mesh: DynamicMesh) {
        _activeSketchContext?.dynamicMesh(mesh)
    }

    /// 動的メッシュを作成
    public func createDynamicMesh() -> DynamicMesh {
        activeContext().createDynamicMesh()
    }

    public func loadModel(_ path: String) -> Mesh? {
        _activeSketchContext?.loadModel(path)
    }

    // MARK: Compute

    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try activeContext().createComputeKernel(source: source, function: function)
    }

    public func createBuffer<T>(count: Int, type: T.Type) -> GPUBuffer<T>? {
        _activeSketchContext?.createBuffer(count: count, type: type)
    }

    public func createBuffer<T>(_ data: [T]) -> GPUBuffer<T>? {
        _activeSketchContext?.createBuffer(data)
    }

    public func dispatch(
        _ kernel: ComputeKernel,
        threads: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        _activeSketchContext?.dispatch(kernel, threads: threads, configure)
    }

    public func dispatch(
        _ kernel: ComputeKernel,
        width: Int,
        height: Int,
        _ configure: (MTLComputeCommandEncoder) -> Void
    ) {
        _activeSketchContext?.dispatch(kernel, width: width, height: height, configure)
    }

    public func computeBarrier() {
        _activeSketchContext?.computeBarrier()
    }
}

// MARK: - Particle System

extension Sketch {
    /// GPU パーティクルシステムを作成
    public func createParticleSystem(count: Int = 100_000) throws -> ParticleSystem {
        try activeContext().createParticleSystem(count: count)
    }

    /// パーティクルシステムを更新（compute() 内で呼ぶ）
    public func updateParticles(_ system: ParticleSystem) {
        _activeSketchContext?.updateParticles(system)
    }

    /// パーティクルシステムを描画（draw() 内で呼ぶ）
    public func drawParticles(_ system: ParticleSystem) {
        _activeSketchContext?.drawParticles(system)
    }
}

// MARK: - Audio

extension Sketch {
    /// オーディオ入力アナライザーを作成
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        activeContext().createAudioInput(fftSize: fftSize)
    }
}

// MARK: - OSC

extension Sketch {
    /// OSC レシーバーを作成
    public func createOSCReceiver(port: UInt16) -> OSCReceiver {
        activeContext().createOSCReceiver(port: port)
    }
}

// MARK: - Tween

extension Sketch {
    /// Tween を作成・登録（自動的に TweenManager に追加される）
    @discardableResult
    public func tween<T: Interpolatable>(
        from: T, to: T, duration: Float, easing: @escaping EasingFunction = easeInOutCubic
    ) -> Tween<T> {
        activeContext().tween(from: from, to: to, duration: duration, easing: easing)
    }
}

// MARK: - Shader Hot Reload

extension Sketch {
    /// シェーダーソースを再コンパイルしてパイプラインキャッシュをクリアする
    public func reloadShader(key: String, source: String) throws {
        try activeContext().reloadShader(key: key, source: source)
    }

    /// 外部ファイルからシェーダーを再読み込みする
    public func reloadShaderFromFile(key: String, path: String) throws {
        try activeContext().reloadShaderFromFile(key: key, path: path)
    }

    /// 外部ファイルから MSL ソースを読み込んでマテリアルを作成する
    public func createMaterialFromFile(path: String, fragmentFunction: String, vertexFunction: String? = nil) throws -> CustomMaterial {
        try activeContext().createMaterialFromFile(path: path, fragmentFunction: fragmentFunction, vertexFunction: vertexFunction)
    }
}

// MARK: - GUI

extension Sketch {
    /// パラメータ GUI インスタンス
    public var gui: ParameterGUI {
        activeContext().gui
    }
}

// MARK: - Performance HUD

extension Sketch {
    /// パフォーマンス HUD を有効化
    public func enablePerformanceHUD() {
        _activeSketchContext?.enablePerformanceHUD()
    }

    /// パフォーマンス HUD を無効化
    public func disablePerformanceHUD() {
        _activeSketchContext?.disablePerformanceHUD()
    }
}

// MARK: - Post Process

extension Sketch {
    /// カスタムポストプロセスエフェクトを作成
    public func createPostEffect(name: String, source: String, fragmentFunction: String) throws -> CustomPostEffect {
        try activeContext().createPostEffect(name: name, source: source, fragmentFunction: fragmentFunction)
    }

    /// ポストプロセスエフェクトを追加
    public func addPostEffect(_ effect: PostEffect) {
        _activeSketchContext?.addPostEffect(effect)
    }

    /// ポストプロセスエフェクトを削除
    public func removePostEffect(at index: Int) {
        _activeSketchContext?.removePostEffect(at: index)
    }

    /// 全ポストプロセスエフェクトを削除
    public func clearPostEffects() {
        _activeSketchContext?.clearPostEffects()
    }

    /// ポストプロセスエフェクトを一括設定
    public func setPostEffects(_ effects: [PostEffect]) {
        _activeSketchContext?.setPostEffects(effects)
    }
}

// MARK: - Cursor Control

extension Sketch {
    /// カーソルを表示
    public func cursor() {
        _activeSketchContext?.cursor()
    }

    /// カーソルを非表示
    public func noCursor() {
        _activeSketchContext?.noCursor()
    }
}

// MARK: - Sound File (D-16)

extension Sketch {
    /// オーディオファイルを読み込む
    public func loadSound(_ path: String) throws -> SoundFile {
        try activeContext().loadSound(path)
    }
}

// MARK: - MIDI (D-17)

extension Sketch {
    /// MIDI マネージャーを作成
    public func createMIDI() -> MIDIManager {
        activeContext().createMIDI()
    }
}

// MARK: - GIF Export (D-19)

extension Sketch {
    /// GIF 録画を開始
    public func beginGIFRecord(fps: Int = 15) {
        _activeSketchContext?.beginGIFRecord(fps: fps)
    }

    /// GIF 録画を終了してファイルに書き出し
    public func endGIFRecord(_ path: String? = nil) throws {
        try activeContext().endGIFRecord(path)
    }
}

// MARK: - Physics 2D

extension Sketch {
    /// 2D 物理ワールドを作成
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        Physics2D(cellSize: cellSize)
    }
}

// MARK: - Orbit Camera (D-20)

extension Sketch {
    /// オービットコントロールを有効化（draw() 内で呼ぶ）
    public func orbitControl() {
        _activeSketchContext?.orbitControl()
    }

    /// オービットカメラへのアクセス
    public var orbitCamera: OrbitCamera {
        activeContext().orbitCamera
    }
}

// MARK: - Scene Graph

extension Sketch {
    /// ノードを作成
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// シーングラフを描画
    public func drawScene(_ root: Node) {
        _activeSketchContext?.drawScene(root)
    }
}

// MARK: - Render Graph

extension Sketch {
    /// ソースパスを作成
    public func createSourcePass(label: String, width: Int, height: Int) -> SourcePass? {
        _activeSketchContext?.createSourcePass(label: label, width: width, height: height)
    }

    /// エフェクトパスを作成
    public func createEffectPass(_ input: RenderPassNode, effects: [PostEffect]) -> EffectPass? {
        _activeSketchContext?.createEffectPass(input, effects: effects)
    }

    /// マージパスを作成
    public func createMergePass(_ a: RenderPassNode, _ b: RenderPassNode, blend: MergePass.BlendType) -> MergePass? {
        _activeSketchContext?.createMergePass(a, b, blend: blend)
    }

    /// レンダーグラフを設定
    public func setRenderGraph(_ graph: RenderGraph?) {
        _activeSketchContext?.setRenderGraph(graph)
    }
}

// MARK: - @main Entry Point

extension Sketch {
    /// `@main` エントリポイント
    public static func main() {
        SketchRunner.run(sketchType: Self.self)
    }
}

// MARK: - SketchConfig

/// スケッチの設定
public struct SketchConfig: Sendable {
    /// テクスチャの幅（ピクセル）
    public var width: Int

    /// テクスチャの高さ（ピクセル）
    public var height: Int

    /// ウィンドウタイトル
    public var title: String

    /// フレームレート
    public var fps: Int

    /// Syphonサーバー名（nilなら無効）
    public var syphonName: String?

    /// ウィンドウサイズのスケール（テクスチャサイズ × scale）
    public var windowScale: Float

    /// フルスクリーンで起動
    public var fullScreen: Bool

    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        windowScale: Float = 0.5,
        fullScreen: Bool = false
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.windowScale = windowScale
        self.fullScreen = fullScreen
    }
}
