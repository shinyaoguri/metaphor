import Metal
import simd

/// 3Dオフスクリーン描画バッファを提供します（`createGraphics3D()` で使用）。
///
/// 独立した Canvas3D を所有し、メインキャンバスとは別に3Dコンテンツを描画できます。
/// 結果は MImage として取得し、`image()` でメインキャンバスに描画できます。
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

    /// 幅をピクセル単位で返します。
    public var width: Float { canvas3D.width }

    /// 高さをピクセル単位で返します。
    public var height: Float { canvas3D.height }

    /// 内部カラーテクスチャを返します。
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
            throw MetaphorError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        self.textureManager = try TextureManager(
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

    /// オプションの時間値でアニメーション用の描画を開始します。
    /// - Parameter time: Canvas3D に渡される経過時間。
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

    /// 描画を終了し GPU の完了を待機します。
    public func endDraw() {
        canvas3D.end()
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

    // MARK: - Camera

    /// カメラの位置と向きを設定します。
    /// - Parameters:
    ///   - eye: カメラ位置。
    ///   - center: 注視点。
    ///   - up: 上方向ベクトル。
    public func camera(
        eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) { canvas3D.camera(eye: eye, center: center, up: up) }

    /// 透視投影を設定します。
    /// - Parameters:
    ///   - fov: ラジアン単位の視野角。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func perspective(
        fov: Float = .pi / 3, near: Float = 0.1, far: Float = 10000
    ) { canvas3D.perspective(fov: fov, near: near, far: far) }

    /// 正射影投影を設定します。
    /// - Parameters:
    ///   - left: 左クリッピング面。
    ///   - right: 右クリッピング面。
    ///   - bottom: 下クリッピング面。
    ///   - top: 上クリッピング面。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -10, far: Float = 10000
    ) { canvas3D.ortho(left: left, right: right, bottom: bottom, top: top, near: near, far: far) }

    // MARK: - Lighting

    /// デフォルトライティングを有効にします。
    public func lights() { canvas3D.lights() }

    /// すべてのライティングを無効にします。
    public func noLights() { canvas3D.noLights() }

    /// 指定された方向でディレクショナルライトを追加します。
    /// - Parameters:
    ///   - x: ライト方向のX成分。
    ///   - y: ライト方向のY成分。
    ///   - z: ライト方向のZ成分。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        canvas3D.directionalLight(x, y, z)
    }

    /// 指定された方向と色でディレクショナルライトを追加します。
    /// - Parameters:
    ///   - x: ライト方向のX成分。
    ///   - y: ライト方向のY成分。
    ///   - z: ライト方向のZ成分。
    ///   - color: ライトの色。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        canvas3D.directionalLight(x, y, z, color: color)
    }

    /// 指定された位置にポイントライトを追加します。
    /// - Parameters:
    ///   - x: ライト位置X。
    ///   - y: ライト位置Y。
    ///   - z: ライト位置Z。
    ///   - color: ライトの色。
    ///   - falloff: 減衰ファクター。
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white, falloff: Float = 0.1
    ) {
        canvas3D.pointLight(x, y, z, color: color, falloff: falloff)
    }

    /// 指定された位置と方向でスポットライトを追加します。
    /// - Parameters:
    ///   - x: ライト位置X。
    ///   - y: ライト位置Y。
    ///   - z: ライト位置Z。
    ///   - dirX: 方向のX成分。
    ///   - dirY: 方向のY成分。
    ///   - dirZ: 方向のZ成分。
    ///   - angle: ラジアン単位のコーン半角。
    ///   - falloff: 減衰ファクター。
    ///   - color: ライトの色。
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = .pi / 6, falloff: Float = 0.01, color: Color = .white
    ) {
        canvas3D.spotLight(x, y, z, dirX, dirY, dirZ, angle: angle, falloff: falloff, color: color)
    }

    /// アンビエントライトの強度を設定します。
    /// - Parameter strength: アンビエントライトの強度。
    public func ambientLight(_ strength: Float) { canvas3D.ambientLight(strength) }

    /// RGB値でアンビエントライトの色を設定します。
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) { canvas3D.ambientLight(r, g, b) }

    // MARK: - Material

    /// スペキュラハイライトの色を設定します。
    /// - Parameter color: スペキュラ色。
    public func specular(_ color: Color) { canvas3D.specular(color) }

    /// スペキュラハイライトをグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func specular(_ gray: Float) { canvas3D.specular(gray) }

    /// スペキュラハイライトの光沢指数を設定します。
    /// - Parameter value: 光沢指数。
    public func shininess(_ value: Float) { canvas3D.shininess(value) }

    /// エミッシブ色を設定します。
    /// - Parameter color: エミッシブ色。
    public func emissive(_ color: Color) { canvas3D.emissive(color) }

    /// エミッシブをグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func emissive(_ gray: Float) { canvas3D.emissive(gray) }

    /// PBR シェーディングのメタリックファクターを設定します。
    /// - Parameter value: メタリックファクター（0.0〜1.0）。
    public func metallic(_ value: Float) { canvas3D.metallic(value) }

    /// PBR シェーディングのラフネスファクターを設定します。
    /// - Parameter value: ラフネスファクター（0.0〜1.0）。
    public func roughness(_ value: Float) { canvas3D.roughness(value) }

    /// PBR シェーディングのアンビエントオクルージョンファクターを設定します。
    /// - Parameter value: アンビエントオクルージョンファクター（0.0〜1.0）。
    public func ambientOcclusion(_ value: Float) { canvas3D.ambientOcclusion(value) }

    /// PBR シェーディングを有効または無効にします。
    /// - Parameter enabled: PBR シェーディングを使用するかどうか。
    public func pbr(_ enabled: Bool) { canvas3D.pbr(enabled) }

    /// 後続の描画呼び出しにカスタムマテリアルを設定します。
    /// - Parameter custom: 適用するカスタムマテリアル。
    public func material(_ custom: CustomMaterial) { canvas3D.material(custom) }

    /// デフォルトマテリアルにリセットします。
    public func noMaterial() { canvas3D.noMaterial() }

    // MARK: - Texture

    /// 後続の3Dプリミティブのテクスチャを設定します。
    /// - Parameter img: テクスチャとして使用する画像。
    public func texture(_ img: MImage) { canvas3D.texture(img) }

    /// テクスチャリングを無効にします。
    public func noTexture() { canvas3D.noTexture() }

    // MARK: - Transform

    /// 現在のモデル行列をスタックにプッシュします。
    public func pushMatrix() { canvas3D.pushMatrix() }

    /// 最後に保存したモデル行列をスタックからポップします。
    public func popMatrix() { canvas3D.popMatrix() }

    /// モデル行列を平行移動します。
    /// - Parameters:
    ///   - x: X方向の平行移動量。
    ///   - y: Y方向の平行移動量。
    ///   - z: Z方向の平行移動量。
    public func translate(_ x: Float, _ y: Float, _ z: Float) { canvas3D.translate(x, y, z) }

    /// X軸周りに回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateX(_ angle: Float) { canvas3D.rotateX(angle) }

    /// Y軸周りに回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateY(_ angle: Float) { canvas3D.rotateY(angle) }

    /// Z軸周りに回転します。
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotateZ(_ angle: Float) { canvas3D.rotateZ(angle) }

    /// 各軸のファクターでモデル行列をスケーリングします。
    /// - Parameters:
    ///   - x: Xスケールファクター。
    ///   - y: Yスケールファクター。
    ///   - z: Zスケールファクター。
    public func scale(_ x: Float, _ y: Float, _ z: Float) { canvas3D.scale(x, y, z) }

    /// モデル行列を均一にスケーリングします。
    /// - Parameter s: 均一スケールファクター。
    public func scale(_ s: Float) { canvas3D.scale(s) }

    // MARK: - Style

    /// 塗りつぶし色を設定します。
    /// - Parameter color: 塗りつぶし色。
    public func fill(_ color: Color) { canvas3D.fill(color) }

    /// チャンネル値で塗りつぶし色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas3D.fill(v1, v2, v3, a) }

    /// 塗りつぶしをグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func fill(_ gray: Float) { canvas3D.fill(gray) }

    /// 塗りつぶしをグレースケール値とアルファで設定します。
    /// - Parameters:
    ///   - gray: グレースケール値。
    ///   - alpha: アルファ値。
    public func fill(_ gray: Float, _ alpha: Float) { canvas3D.fill(gray, alpha) }

    /// シェイプの塗りつぶしを無効にします。
    public func noFill() { canvas3D.noFill() }

    /// ストローク色を設定します。
    /// - Parameter color: ストローク色。
    public func stroke(_ color: Color) { canvas3D.stroke(color) }

    /// チャンネル値でストローク色を設定します。
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) { canvas3D.stroke(v1, v2, v3, a) }

    /// ストロークをグレースケール値で設定します。
    /// - Parameter gray: グレースケール値。
    public func stroke(_ gray: Float) { canvas3D.stroke(gray) }

    /// ストロークをグレースケール値とアルファで設定します。
    /// - Parameters:
    ///   - gray: グレースケール値。
    ///   - alpha: アルファ値。
    public func stroke(_ gray: Float, _ alpha: Float) { canvas3D.stroke(gray, alpha) }

    /// シェイプのストロークを無効にします。
    public func noStroke() { canvas3D.noStroke() }

    /// カラーモードとオプションの最大チャンネル値を設定します。
    /// - Parameters:
    ///   - space: カラースペース（RGB または HSB）。
    ///   - max1: 第1チャンネルの最大値。
    ///   - max2: 第2チャンネルの最大値。
    ///   - max3: 第3チャンネルの最大値。
    ///   - maxA: アルファチャンネルの最大値。
    public func colorMode(
        _ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0,
        _ max3: Float = 1.0, _ maxA: Float = 1.0
    ) { canvas3D.colorMode(space, max1, max2, max3, maxA) }

    /// 全チャンネルに均一な最大値でカラーモードを設定します。
    /// - Parameters:
    ///   - space: カラースペース。
    ///   - maxAll: 全チャンネルに適用される最大値。
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) { canvas3D.colorMode(space, maxAll) }

    // MARK: - Primitives

    /// 個別の寸法でボックスを描画します。
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    public func box(_ width: Float, _ height: Float, _ depth: Float) { canvas3D.box(width, height, depth) }

    /// 均一なサイズでキューブを描画します。
    /// - Parameter size: 辺の長さ。
    public func box(_ size: Float) { canvas3D.box(size) }

    /// 球体を描画します。
    /// - Parameters:
    ///   - radius: 球体の半径。
    ///   - detail: テッセレーションの詳細レベル。
    public func sphere(_ radius: Float, detail: Int = 24) { canvas3D.sphere(radius, detail: detail) }

    /// 平面を描画します。
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    public func plane(_ width: Float, _ height: Float) { canvas3D.plane(width, height) }

    /// シリンダーを描画します。
    /// - Parameters:
    ///   - radius: シリンダーの半径。
    ///   - height: シリンダーの高さ。
    ///   - detail: テッセレーションの詳細レベル。
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) { canvas3D.cylinder(radius: radius, height: height, detail: detail) }

    /// コーンを描画します。
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: コーンの高さ。
    ///   - detail: テッセレーションの詳細レベル。
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) { canvas3D.cone(radius: radius, height: height, detail: detail) }

    /// トーラスを描画します。
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブの中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: テッセレーションの詳細レベル。
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) { canvas3D.torus(ringRadius: ringRadius, tubeRadius: tubeRadius, detail: detail) }

    /// カスタムメッシュを描画します。
    /// - Parameter mesh: レンダリングするメッシュ。
    public func mesh(_ mesh: Mesh) { canvas3D.mesh(mesh) }
}
