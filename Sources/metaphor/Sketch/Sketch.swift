import AppKit
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

    /// キーが押された
    func keyPressed()

    /// キーが離された
    func keyReleased()
}

// MARK: - Active Context (internal global)

/// SketchRunnerが設定するアクティブなコンテキスト
@MainActor
var _activeSketchContext: SketchContext?

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
        _activeSketchContext!.input
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

// MARK: - Drawing Methods (ctx省略用)

extension Sketch {

    // MARK: Background

    public func background(_ color: Color) {
        _activeSketchContext?.background(color)
    }

    public func background(_ gray: Float) {
        _activeSketchContext?.background(gray)
    }

    // MARK: Style

    public func fill(_ color: Color) {
        _activeSketchContext?.fill(color)
    }

    public func fill(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) {
        _activeSketchContext?.fill(r, g, b, a)
    }

    public func noFill() {
        _activeSketchContext?.noFill()
    }

    public func stroke(_ color: Color) {
        _activeSketchContext?.stroke(color)
    }

    public func stroke(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) {
        _activeSketchContext?.stroke(r, g, b, a)
    }

    public func noStroke() {
        _activeSketchContext?.noStroke()
    }

    public func strokeWeight(_ weight: Float) {
        _activeSketchContext?.strokeWeight(weight)
    }

    public func blendMode(_ mode: BlendMode) {
        _activeSketchContext?.blendMode(mode)
    }

    // MARK: Image

    public func loadImage(_ path: String) throws -> MImage {
        try _activeSketchContext!.loadImage(path)
    }

    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        _activeSketchContext?.image(img, x, y)
    }

    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.image(img, x, y, w, h)
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

    public func text(_ string: String, _ x: Float, _ y: Float) {
        _activeSketchContext?.text(string, x, y)
    }

    // MARK: Screenshot

    public func save(_ path: String) {
        _activeSketchContext?.save(path)
    }

    public func save() {
        _activeSketchContext?.save()
    }

    // MARK: 2D Transform Stack

    public func push() {
        _activeSketchContext?.push()
    }

    public func pop() {
        _activeSketchContext?.pop()
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

    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        _activeSketchContext?.ellipse(x, y, w, h)
    }

    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        _activeSketchContext?.circle(x, y, diameter)
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

    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float
    ) {
        _activeSketchContext?.arc(x, y, w, h, startAngle, stopAngle)
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

    public func endShape(_ close: CloseMode = .open) {
        _activeSketchContext?.endShape(close)
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

    // MARK: Compute

    public func createComputeKernel(source: String, function: String) throws -> ComputeKernel {
        try _activeSketchContext!.createComputeKernel(source: source, function: function)
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

    public init(
        width: Int = 1920,
        height: Int = 1080,
        title: String = "metaphor",
        fps: Int = 60,
        syphonName: String? = nil,
        windowScale: Float = 0.5
    ) {
        self.width = width
        self.height = height
        self.title = title
        self.fps = fps
        self.syphonName = syphonName
        self.windowScale = windowScale
    }
}
