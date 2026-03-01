import Metal
import simd

/// 3D オフスクリーン描画バッファ（createGraphics3D() で使用）
///
/// 独自の Canvas3D を持ち、メインキャンバスとは独立して 3D 描画ができる。
/// 描画結果は MImage として取り出し、メインキャンバスに `image()` で描画可能。
///
/// ```swift
/// let pg3d = createGraphics3D(800, 600)
/// pg3d.beginDraw()
/// pg3d.lights()
/// pg3d.fill(.red)
/// pg3d.rotateY(time)
/// pg3d.box(200)
/// pg3d.endDraw()
/// image(pg3d, 0, 0)
/// ```
@MainActor
public final class Graphics3D {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureManager: TextureManager
    private let canvas3D: Canvas3D
    private var commandBuffer: MTLCommandBuffer?
    private var encoder: MTLRenderCommandEncoder?
    private var drawTime: Float = 0

    /// 幅（ピクセル）
    public var width: Float { canvas3D.width }

    /// 高さ（ピクセル）
    public var height: Float { canvas3D.height }

    /// 内部テクスチャ
    public var texture: MTLTexture { textureManager.colorTexture }

    // MARK: - Initialization

    init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Int,
        height: Int
    ) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw GraphicsError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        self.textureManager = TextureManager(
            device: device, width: width, height: height, sampleCount: 1
        )
        self.canvas3D = try Canvas3D(
            device: device,
            shaderLibrary: shaderLibrary,
            depthStencilCache: depthStencilCache,
            width: Float(width),
            height: Float(height),
            sampleCount: 1
        )
    }

    // MARK: - Draw Lifecycle

    /// 描画開始
    public func beginDraw(time: Float = 0) {
        guard let cb = commandQueue.makeCommandBuffer() else { return }
        self.commandBuffer = cb
        self.drawTime = time

        guard let enc = cb.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) else {
            cb.commit()
            self.commandBuffer = nil
            return
        }
        self.encoder = enc
        canvas3D.begin(encoder: enc, time: time)
    }

    /// 描画終了（GPU 完了を待つ）
    public func endDraw() {
        canvas3D.end()
        encoder?.endEncoding()
        encoder = nil
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        commandBuffer = nil
    }

    // MARK: - MImage Conversion

    /// テクスチャを MImage として取得
    public func toImage() -> MImage {
        MImage(texture: textureManager.colorTexture)
    }

    // MARK: - Camera

    public func camera(
        eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) { canvas3D.camera(eye: eye, center: center, up: up) }

    public func perspective(
        fov: Float = .pi / 3, near: Float = 0.1, far: Float = 10000
    ) { canvas3D.perspective(fov: fov, near: near, far: far) }

    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -10, far: Float = 10000
    ) { canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far) }

    // MARK: - Lighting

    public func lights() { canvas3D.lights() }
    public func noLights() { canvas3D.noLights() }

    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white, falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = .pi / 6, falloff: Float = 0.01, color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    public func ambientLight(_ strength: Float) { canvas3D.ambientLight(strength) }
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) { canvas3D.ambientLight(r, g, b) }

    // MARK: - Material

    public func specular(_ color: Color) { canvas3D.specular(color) }
    public func specular(_ gray: Float) { canvas3D.specular(gray) }
    public func shininess(_ value: Float) { canvas3D.shininess(value) }
    public func emissive(_ color: Color) { canvas3D.emissive(color) }
    public func emissive(_ gray: Float) { canvas3D.emissive(gray) }
    public func metallic(_ value: Float) { canvas3D.metallic(value) }
    public func material(_ custom: CustomMaterial) { canvas3D.material(custom) }
    public func noMaterial() { canvas3D.noMaterial() }

    // MARK: - Texture

    public func texture(_ img: MImage) { canvas3D.texture(img) }
    public func noTexture() { canvas3D.noTexture() }

    // MARK: - Transform

    public func pushMatrix() { canvas3D.pushMatrix() }
    public func popMatrix() { canvas3D.popMatrix() }
    public func translate(_ x: Float, _ y: Float, _ z: Float) { canvas3D.translate(x, y, z) }
    public func rotateX(_ angle: Float) { canvas3D.rotateX(angle) }
    public func rotateY(_ angle: Float) { canvas3D.rotateY(angle) }
    public func rotateZ(_ angle: Float) { canvas3D.rotateZ(angle) }
    public func scale(_ x: Float, _ y: Float, _ z: Float) { canvas3D.scale(x, y, z) }
    public func scale(_ s: Float) { canvas3D.scale(s) }

    // MARK: - Style

    public func fill(_ color: Color) { canvas3D.fill(color) }
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas3D.fill(v1, v2, v3, a) }
    public func fill(_ gray: Float) { canvas3D.fill(gray) }
    public func fill(_ gray: Float, _ alpha: Float) { canvas3D.fill(gray, alpha) }
    public func noFill() { canvas3D.noFill() }

    public func stroke(_ color: Color) { canvas3D.stroke(color) }
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas3D.stroke(v1, v2, v3, a) }
    public func stroke(_ gray: Float) { canvas3D.stroke(gray) }
    public func stroke(_ gray: Float, _ alpha: Float) { canvas3D.stroke(gray, alpha) }
    public func noStroke() { canvas3D.noStroke() }

    public func colorMode(
        _ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0,
        _ max3: Float = 1.0, _ maxA: Float = 1.0
    ) { canvas3D.colorMode(space, max1, max2, max3, maxA) }
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas3D.colorMode(space, maxAll) }

    // MARK: - Primitives

    public func box(_ width: Float, _ height: Float, _ depth: Float) { canvas3D.box(width, height, depth) }
    public func box(_ size: Float) { canvas3D.box(size) }
    public func sphere(_ radius: Float, detail: Int = 24) { canvas3D.sphere(radius, detail: detail) }
    public func plane(_ width: Float, _ height: Float) { canvas3D.plane(width, height) }
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) { canvas3D.cylinder(radius: radius, height: height, detail: detail) }
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) { canvas3D.cone(radius: radius, height: height, detail: detail) }
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) { canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail) }
    public func mesh(_ mesh: Mesh) { canvas3D.mesh(mesh) }
}
