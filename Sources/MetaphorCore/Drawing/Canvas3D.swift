import Metal
import simd

// MARK: - Canvas3D ユニフォーム

/// Canvas3D シェーダー用のユニフォームデータ。MSL の `Canvas3DUniforms` レイアウトに対応します。
struct Canvas3DUniforms {
    var modelMatrix: float4x4
    var viewProjectionMatrix: float4x4
    var normalMatrix: float4x4
    var color: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var time: Float
    var lightCount: UInt32
    var hasTexture: UInt32
    var _pad: UInt32 = 0
}

// MARK: - Light3D

/// GPU 互換のライトデータ（64バイト、16バイトアラインメント）。
struct Light3D {
    var positionAndType: SIMD4<Float>           // xyz=位置, w=タイプ(0=ディレクショナル,1=ポイント,2=スポット)
    var directionAndCutoff: SIMD4<Float>        // xyz=方向, w=cos(内側カットオフ)
    var colorAndIntensity: SIMD4<Float>         // xyz=色, w=強度
    var attenuationAndOuterCutoff: SIMD4<Float> // xyz=(定数,線形,二次), w=cos(外側カットオフ)

    static let zero = Light3D(
        positionAndType: .zero,
        directionAndCutoff: .zero,
        colorAndIntensity: .zero,
        attenuationAndOuterCutoff: .zero
    )
}

// MARK: - Material3D

/// GPU 互換のマテリアルデータ（64バイト）。
struct Material3D {
    var ambientColor: SIMD4<Float>         // xyz=アンビエント色
    var specularAndShininess: SIMD4<Float> // xyz=スペキュラ色, w=光沢度
    var emissiveAndMetallic: SIMD4<Float>  // xyz=エミッシブ色, w=メタリック
    var pbrParams: SIMD4<Float>            // x=ラフネス, y=usePBR(0/1), z=ao, w=予約

    static let `default` = Material3D(
        ambientColor: SIMD4(0.2, 0.2, 0.2, 0),
        specularAndShininess: SIMD4(0, 0, 0, 32),
        emissiveAndMetallic: SIMD4(0, 0, 0, 0),
        pbrParams: SIMD4(0.5, 0, 1, 0)    // roughness=0.5, usePBR=off, ao=1, reserved=0
    )
}

// MARK: - Canvas3D

/// イミディエイトモード 3D 描画コンテキストを提供します。
///
/// p5.js WEBGL スタイルの API で 3D シーンを描画します。
/// Canvas2D と同じレンダーコマンドエンコーダーを共有し、3D 描画コマンドを即時実行します。
@MainActor
public final class Canvas3D: CanvasStyle {
    // MARK: - Metal リソース

    private let device: MTLDevice
    private let shaderLibrary: ShaderLibrary
    private let sampleCount: Int
    private let pipelineState: MTLRenderPipelineState
    private let texturedPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState?
    private let dummyShadowTexture: MTLTexture?

    // インスタンスレンダリングパイプライン
    private let instancedPipelineState: MTLRenderPipelineState
    private let instancedTexturedPipelineState: MTLRenderPipelineState
    private let instanceBatcher: InstanceBatcher3D

    private static let maxLights = 8

    // MARK: - カスタムマテリアル状態

    private var currentCustomMaterial: CustomMaterial?
    private var customPipelineCache: [String: MTLRenderPipelineState] = [:]

    // MARK: - 寸法

    /// 3D キャンバスの幅（ポイント単位）。
    public let width: Float

    /// 3D キャンバスの高さ（ポイント単位）。
    public let height: Float

    // MARK: - フレームごとの状態

    private var encoder: MTLRenderCommandEncoder?
    private var currentTime: Float = 0

    // MARK: - カメラ状態

    private var cameraEye: SIMD3<Float> = SIMD3(0, 0, 5)
    private var cameraCenter: SIMD3<Float> = .zero
    private var cameraUp: SIMD3<Float> = SIMD3(0, 1, 0)
    private static let defaultFov: Float = Float.pi / 3
    private var fov: Float = Canvas3D.defaultFov
    private var nearPlane: Float = 0.1
    private var farPlane: Float = 10000
    private var viewProjectionDirty: Bool = true
    private var cachedViewProjection: float4x4 = .identity
    private var useOrthographic: Bool = false
    private var orthoLeft: Float = 0
    private var orthoRight: Float = 0
    private var orthoBottom: Float = 0
    private var orthoTop: Float = 0

    // MARK: - ライティング状態

    private var lightArray: [Light3D] = []
    private var ambientColor: SIMD3<Float> = SIMD3(0.2, 0.2, 0.2)
    private var userSetAmbient: Bool = false

    // MARK: - マテリアル状態

    var currentMaterial: Material3D = .default

    // MARK: - テクスチャ状態

    var currentTexture: MTLTexture?

    // MARK: - 変換スタック

    private struct StyleState3D {
        var transform: float4x4
        var fillColor: SIMD4<Float>
        var hasFill: Bool
        var hasStroke: Bool
        var strokeColor: SIMD4<Float>
        var material: Material3D
        var customMaterial: CustomMaterial?
        var texture: MTLTexture?
        var colorModeConfig: ColorModeConfig
    }

    private var stateStack: [StyleState3D] = []
    private var matrixStack: [float4x4] = []
    var currentTransform: float4x4 = .identity

    // MARK: - スタイル

    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    public var hasFill: Bool = true
    public var hasStroke: Bool = false
    public var strokeColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    public var colorModeConfig: ColorModeConfig = ColorModeConfig()

    // MARK: - シェイプ構築状態（3D beginShape/endShape）

    private var isRecordingShape3D: Bool = false
    private var shapeMode3D: ShapeMode = .polygon
    private var shapeVertices3D: [Vertex3D] = []
    private var pendingNormal: SIMD3<Float>?

    // MARK: - メッシュキャッシュ

    private struct CachedMesh {
        let mesh: Mesh
        var lastUsedFrame: Int
    }

    private var meshCache: [String: CachedMesh] = [:]
    private var meshCacheFrameCounter: Int = 0
    private static let maxMeshCacheSize = 64

    // MARK: - シャドウマッピング状態

    /// シャドウレンダリングに使用するシャドウマップ。シャドウ無効時は `nil`。
    var shadowMap: ShadowMap?

    /// 現在のフレームでシャドウ深度パス用に記録されたドローコール。
    private(set) var recordedDrawCalls: [DrawCall3D] = []

    // MARK: - 初期化

    /// レンダラーからキャンバスを生成します。デバイス、シェーダーライブラリ、テクスチャサイズを継承します。
    ///
    /// - Parameter renderer: 設定の派生元となるレンダラー。
    /// - Throws: パイプラインステートの生成に失敗した場合にエラー。
    public convenience init(renderer: MetaphorRenderer) throws {
        try self.init(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: Float(renderer.textureManager.width),
            height: Float(renderer.textureManager.height),
            sampleCount: renderer.textureManager.sampleCount
        )
    }

    /// 明示的な Metal リソースと寸法でキャンバスを生成します。
    ///
    /// - Parameters:
    ///   - device: リソース割り当てに使用する Metal デバイス。
    ///   - shaderLibrary: 組み込みシェーダー関数を含むシェーダーライブラリ。
    ///   - depthStencilCache: 深度ステンシルステートのキャッシュ。
    ///   - width: キャンバスの幅（ポイント単位）。
    ///   - height: キャンバスの高さ（ポイント単位）。
    ///   - sampleCount: MSAA サンプル数（デフォルト: 1）。
    /// - Throws: パイプラインステートの生成に失敗した場合にエラー。
    public init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Float,
        height: Float,
        sampleCount: Int = 1
    ) throws {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.sampleCount = sampleCount
        self.width = width
        self.height = height

        // 非テクスチャパイプライン
        let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DVertex,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DFragment,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        self.pipelineState = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .vertexLayout(.positionNormalColor)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        // テクスチャパイプライン
        let texVertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        let texFragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas3DTextured
        )
        self.texturedPipelineState = try PipelineFactory(device: device)
            .vertex(texVertexFn)
            .fragment(texFragmentFn)
            .vertexLayout(.positionNormalUV)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        self.depthState = depthStencilCache.state(for: .readWrite)

        // インスタンスパイプライン（非テクスチャ）
        let instVertexFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.vertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        let instFragmentFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.fragmentFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        self.instancedPipelineState = try PipelineFactory(device: device)
            .vertex(instVertexFn)
            .fragment(instFragmentFn)
            .vertexLayout(.positionNormalColor)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        // インスタンスパイプライン（テクスチャ）
        let instTexVertexFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.texturedVertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        let instTexFragmentFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.texturedFragmentFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        self.instancedTexturedPipelineState = try PipelineFactory(device: device)
            .vertex(instTexVertexFn)
            .fragment(instTexFragmentFn)
            .vertexLayout(.positionNormalUV)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()

        self.instanceBatcher = try InstanceBatcher3D(device: device)

        // ダミー 1x1 シャドウテクスチャ（シャドウ無効時にバインド）
        let dummyDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false
        )
        dummyDesc.usage = .shaderRead
        dummyDesc.storageMode = .private
        self.dummyShadowTexture = device.makeTexture(descriptor: dummyDesc)
    }

    // MARK: - フレームライフサイクル

    /// フレームごとの状態をリセットし、レンダーエンコーダーを設定して新しいフレームを開始します。
    func begin(encoder: MTLRenderCommandEncoder, time: Float, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentTime = time
        // フレームごとの状態をリセット（変換、カメラ、ライト、ドローコール）
        self.currentTransform = .identity
        self.stateStack.removeAll(keepingCapacity: true)
        self.lightArray.removeAll(keepingCapacity: true)
        self.ambientColor = SIMD3(0.2, 0.2, 0.2)
        self.userSetAmbient = false
        self.currentMaterial = .default
        self.currentTexture = nil
        self.currentCustomMaterial = nil
        self.recordedDrawCalls.removeAll(keepingCapacity: true)
        self.meshCacheFrameCounter += 1

        // 各フレームで Processing 風のデフォルトに投影をリセット。
        // カスタム投影には毎フレーム perspective()/ortho() を呼ぶ必要があります。
        let defaultZ = (height / 2) / tan(Canvas3D.defaultFov / 2)
        self.fov = Canvas3D.defaultFov
        self.nearPlane = defaultZ / 10
        self.farPlane = defaultZ * 10
        self.cameraEye = SIMD3(width / 2, height / 2, defaultZ)
        self.cameraCenter = SIMD3(width / 2, height / 2, 0)
        self.cameraUp = SIMD3(0, 1, 0)
        self.viewProjectionDirty = true
        self.useOrthographic = false

        // スタイル状態（fill、stroke）はフレーム間で保持される。
        // Processing の動作に合わせます。
        instanceBatcher.beginFrame(bufferIndex: bufferIndex)
    }

    /// 保留中のインスタンスバッチをフラッシュして現在のフレームを終了します。
    func end() {
        flushInstanceBatch()
        self.encoder = nil
    }

    /// メインレンダリングパス完了後にシャドウ深度パスを実行します。
    func performShadowPass(commandBuffer: MTLCommandBuffer) {
        guard let shadow = shadowMap, !recordedDrawCalls.isEmpty else { return }

        // 最初のディレクショナルライトからライト空間行列を計算
        if let dirLight = lightArray.first(where: { UInt32($0.positionAndType.w) == 0 }) {
            let lightDir = SIMD3(dirLight.directionAndCutoff.x, dirLight.directionAndCutoff.y, dirLight.directionAndCutoff.z)
            shadow.updateLightSpaceMatrix(lightDirection: lightDir, sceneCenter: cameraCenter)
        }

        shadow.render(drawCalls: recordedDrawCalls, commandBuffer: commandBuffer)
    }

    // MARK: - パブリックカメラアクセサ

    /// 現在のビュー投影行列を返します。
    public var currentViewProjection: float4x4 {
        computeViewProjection()
    }

    /// カメラの右方向ベクトルを返します。ビルボーディングに便利です。
    public var currentCameraRight: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        return normalize(cross(cameraUp, z))
    }

    /// カメラの上方向ベクトルを返します。ビルボーディングに便利です。
    public var currentCameraUp: SIMD3<Float> {
        let z = normalize(cameraEye - cameraCenter)
        let x = normalize(cross(cameraUp, z))
        return cross(z, x)
    }

    // MARK: - カメラ

    /// カメラの位置と向きを設定します。
    ///
    /// - Parameters:
    ///   - eye: ワールド空間でのカメラ位置。
    ///   - center: カメラの注視点。
    ///   - up: 上方向ベクトル。
    public func camera(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) {
        self.cameraEye = eye
        self.cameraCenter = center
        self.cameraUp = up
        self.viewProjectionDirty = true
    }

    /// 透視投影パラメータを設定します。
    ///
    /// - Parameters:
    ///   - fov: 垂直視野角（ラジアン）。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func perspective(
        fov: Float = Float.pi / 3,
        near: Float = 0.1,
        far: Float = 10000
    ) {
        self.fov = fov
        self.nearPlane = near
        self.farPlane = far
        self.useOrthographic = false
        self.viewProjectionDirty = true
    }

    /// 正射影に切り替えます。
    ///
    /// - Parameters:
    ///   - left: ビューボリュームの左端（`nil` の場合デフォルト 0）。
    ///   - right: ビューボリュームの右端（`nil` の場合デフォルトはキャンバス幅）。
    ///   - bottom: ビューボリュームの下端（`nil` の場合デフォルトはキャンバス高さ）。
    ///   - top: ビューボリュームの上端（`nil` の場合デフォルト 0）。
    ///   - near: ニアクリッピング面の距離。
    ///   - far: ファークリッピング面の距離。
    public func ortho(
        left: Float? = nil, right: Float? = nil,
        bottom: Float? = nil, top: Float? = nil,
        near: Float = -1000, far: Float = 1000
    ) {
        self.useOrthographic = true
        self.orthoLeft = left ?? 0
        self.orthoRight = right ?? width
        self.orthoBottom = bottom ?? height
        self.orthoTop = top ?? 0
        self.nearPlane = near
        self.farPlane = far
        self.viewProjectionDirty = true
    }

    // MARK: - ライティング

    /// 後方互換性のため、単一のディレクショナルライトでデフォルトライティングを有効にします。
    public func lights() {
        lightArray.removeAll(keepingCapacity: true)
        ambientColor = SIMD3(0.3, 0.3, 0.3)
        currentMaterial.ambientColor = SIMD4(0.3, 0.3, 0.3, 0)

        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        light.directionAndCutoff = SIMD4(-0.5, -1.0, -0.8, 0)
        light.colorAndIntensity = SIMD4(1, 1, 1, 0.7)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    /// シーンからすべてのライトを除去します。
    public func noLights() {
        lightArray.removeAll(keepingCapacity: true)
    }

    /// 指定方向の白色ディレクショナルライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト方向のx成分。
    ///   - y: ライト方向のy成分。
    ///   - z: ライト方向のz成分。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float) {
        directionalLight(x, y, z, color: Color.white)
    }

    /// 指定方向・色のディレクショナルライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト方向のx成分。
    ///   - y: ライト方向のy成分。
    ///   - z: ライト方向のz成分。
    ///   - color: ライトの色。
    public func directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        // ローカル空間の方向をワールド空間に変換（w=0 で平行移動を除外）
        let td = currentTransform * SIMD4(x, y, z, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(0, 0, 0, 0)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, 0)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1, 0, 0, 0)
        lightArray.append(light)
    }

    /// 指定位置にポイントライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト位置のx座標。
    ///   - y: ライト位置のy座標。
    ///   - z: ライト位置のz座標。
    ///   - color: ライトの色。
    ///   - falloff: 減衰フォールオフ係数。
    public func pointLight(
        _ x: Float, _ y: Float, _ z: Float,
        color: Color = .white,
        falloff: Float = 0.1
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        // ローカル空間の位置をワールド空間に変換
        let tp = currentTransform * SIMD4(x, y, z, 1)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 1)
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, 0)
        lightArray.append(light)
    }

    /// 指定位置・方向にスポットライトを追加します。
    ///
    /// - Parameters:
    ///   - x: ライト位置のx座標。
    ///   - y: ライト位置のy座標。
    ///   - z: ライト位置のz座標。
    ///   - dirX: スポットライト方向のx成分。
    ///   - dirY: スポットライト方向のy成分。
    ///   - dirZ: スポットライト方向のz成分。
    ///   - angle: 外側コーン角度（ラジアン）。
    ///   - falloff: 減衰フォールオフ係数。
    ///   - color: ライトの色。
    public func spotLight(
        _ x: Float, _ y: Float, _ z: Float,
        _ dirX: Float, _ dirY: Float, _ dirZ: Float,
        angle: Float = Float.pi / 6,
        falloff: Float = 0.01,
        color: Color = .white
    ) {
        guard lightArray.count < Canvas3D.maxLights else { return }
        ensureAmbientIfFirstLight()
        let innerAngle = angle * 0.8
        // ローカル空間の位置と方向をワールド空間に変換
        let tp = currentTransform * SIMD4(x, y, z, 1)
        let td = currentTransform * SIMD4(dirX, dirY, dirZ, 0)
        var light = Light3D.zero
        light.positionAndType = SIMD4(tp.x, tp.y, tp.z, 2)
        light.directionAndCutoff = SIMD4(td.x, td.y, td.z, cos(innerAngle))
        light.colorAndIntensity = SIMD4(color.r, color.g, color.b, 1.0)
        light.attenuationAndOuterCutoff = SIMD4(1.0, falloff, falloff * 0.1, cos(angle))
        lightArray.append(light)
    }

    /// 全チャンネル均一にアンビエントライトの強度を設定します。
    ///
    /// - Parameter strength: R、G、B に適用されるアンビエントライト強度値。
    public func ambientLight(_ strength: Float) {
        let c = colorModeConfig.toGray(strength)
        ambientColor = SIMD3(c.r, c.g, c.b)
        currentMaterial.ambientColor = SIMD4(c.r, c.g, c.b, 0)
        userSetAmbient = true
    }

    /// 個別の RGB 成分でアンビエントライトの色を設定します。
    ///
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    public func ambientLight(_ r: Float, _ g: Float, _ b: Float) {
        let c = colorModeConfig.toColor(r, g, b, nil)
        ambientColor = SIMD3(c.r, c.g, c.b)
        currentMaterial.ambientColor = SIMD4(c.r, c.g, c.b, 0)
        userSetAmbient = true
    }

    // MARK: - マテリアル

    /// 現在のマテリアルのスペキュラハイライト色を設定します。
    ///
    /// - Parameter color: スペキュラ色。
    public func specular(_ color: Color) {
        currentMaterial.specularAndShininess = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.specularAndShininess.w
        )
    }

    /// グレースケール値でスペキュラハイライト色を設定します。
    ///
    /// - Parameter gray: 全チャンネルに適用されるグレースケール強度。
    public func specular(_ gray: Float) {
        currentMaterial.specularAndShininess = SIMD4(
            gray, gray, gray,
            currentMaterial.specularAndShininess.w
        )
    }

    /// 現在のマテリアルの光沢度指数を設定します。
    ///
    /// - Parameter value: 光沢度指数（値が大きいほどハイライトが鋭くなります）。
    public func shininess(_ value: Float) {
        currentMaterial.specularAndShininess.w = value
    }

    /// 現在のマテリアルのエミッシブ色を設定します。
    ///
    /// - Parameter color: エミッシブ色。
    public func emissive(_ color: Color) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// グレースケール値でエミッシブ色を設定します。
    ///
    /// - Parameter gray: 全チャンネルに適用されるグレースケール強度。
    public func emissive(_ gray: Float) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            gray, gray, gray,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// 現在のマテリアルのメタリック係数を設定します。
    ///
    /// - Parameter value: メタリック係数。0.0（誘電体）から 1.0（完全金属）まで。
    public func metallic(_ value: Float) {
        currentMaterial.emissiveAndMetallic.w = value
    }

    /// PBR ラフネスを設定し、自動的に PBR シェーディングモードを有効にします。
    ///
    /// - Parameter value: ラフネス。0.0（鏡面）から 1.0（完全拡散）まで。
    public func roughness(_ value: Float) {
        currentMaterial.pbrParams.x = value
        currentMaterial.pbrParams.y = 1  // 自動的に PBR モードを有効化
    }

    /// PBR アンビエントオクルージョン係数を設定します。
    ///
    /// - Parameter value: オクルージョン。0.0（完全遮蔽）から 1.0（遮蔽なし）まで。
    public func ambientOcclusion(_ value: Float) {
        currentMaterial.pbrParams.z = value
    }

    /// PBR シェーディングモードを明示的に切り替えます。
    ///
    /// - Parameter enabled: `true` で Cook-Torrance GGX シェーディング、`false` で Blinn-Phong。
    public func pbr(_ enabled: Bool) {
        currentMaterial.pbrParams.y = enabled ? 1 : 0
    }

    // MARK: - カスタムマテリアル

    /// 以降の描画コマンドにカスタムフラグメントシェーダーマテリアルを適用します。
    ///
    /// - Parameter custom: 適用するカスタムマテリアル。
    public func material(_ custom: CustomMaterial) {
        currentCustomMaterial = custom
    }

    /// カスタムマテリアルを除去し、組み込みシェーダーに戻します。
    public func noMaterial() {
        currentCustomMaterial = nil
    }

    // MARK: - テクスチャ

    /// 以降のテクスチャ付き描画コマンドにテクスチャを設定します。
    ///
    /// - Parameter img: テクスチャがバインドされる画像。
    public func texture(_ img: MImage) {
        currentTexture = img.texture
    }

    /// 現在バインドされているテクスチャを除去します。
    public func noTexture() {
        currentTexture = nil
    }

    // MARK: - 変換スタック

    /// 変換、スタイル、マテリアルを含む全状態を保存します。
    public func pushState() {
        stateStack.append(StyleState3D(
            transform: currentTransform,
            fillColor: fillColor,
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            texture: currentTexture,
            colorModeConfig: colorModeConfig
        ))
    }

    /// 直前に保存した状態を復元します。
    public func popState() {
        guard let saved = stateStack.popLast() else { return }
        currentTransform = saved.transform
        fillColor = saved.fillColor
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        strokeColor = saved.strokeColor
        currentMaterial = saved.material
        currentCustomMaterial = saved.customMaterial
        currentTexture = saved.texture
        colorModeConfig = saved.colorModeConfig
    }

    /// 現在の変換行列のみを保存します。
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// 直前に保存した変換行列のみを復元します。
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// 現在の変換に指定オフセットの平行移動を適用します。
    ///
    /// - Parameters:
    ///   - x: x軸方向の移動量。
    ///   - y: y軸方向の移動量。
    ///   - z: z軸方向の移動量。
    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(translation: SIMD3(x, y, z))
    }

    /// 現在の変換をx軸周りに回転させます。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotateX(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationX: angle) }

    /// 現在の変換をy軸周りに回転させます。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotateY(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationY: angle) }

    /// 現在の変換をz軸周りに回転させます。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotateZ(_ angle: Float) { currentTransform = currentTransform * float4x4(rotationZ: angle) }

    /// 各軸に沿った非均一スケールを現在の変換に適用します。
    ///
    /// - Parameters:
    ///   - x: x軸方向のスケール係数。
    ///   - y: y軸方向のスケール係数。
    ///   - z: z軸方向のスケール係数。
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        currentTransform = currentTransform * float4x4(scale: SIMD3(x, y, z))
    }

    /// 全軸に均一スケールを現在の変換に適用します。
    ///
    /// - Parameter s: 均一スケール係数。
    public func scale(_ s: Float) { currentTransform = currentTransform * float4x4(scale: s) }

    /// 現在の変換に指定した行列を乗算します。
    ///
    /// - Parameter matrix: 連結する 4x4 行列。
    public func applyMatrix(_ matrix: float4x4) {
        currentTransform = currentTransform * matrix
    }

    // MARK: - 3D シェイプ

    /// 指定した寸法でボックスを描画します。
    ///
    /// - Parameters:
    ///   - width: ボックスの幅。
    ///   - height: ボックスの高さ。
    ///   - depth: ボックスの奥行き。
    public func box(_ width: Float, _ height: Float, _ depth: Float) {
        let key = "box_\(width)_\(height)_\(depth)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.box(device: device, width: width, height: height, depth: depth) }) else { return }
        drawMesh(mesh)
    }

    /// 同じ寸法の立方体を描画します。
    ///
    /// - Parameter size: 立方体の辺の長さ。
    public func box(_ size: Float) { box(size, size, size) }

    /// 指定した半径とテッセレーション詳細度で球を描画します。
    ///
    /// - Parameters:
    ///   - radius: 球の半径。
    ///   - detail: 経度方向のセグメント数（リングはここから導出されます）。
    public func sphere(_ radius: Float, detail: Int = 24) {
        let rings = max(detail / 2, 4)
        let key = "sphere_\(radius)_\(detail)_\(rings)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.sphere(device: device, radius: radius, segments: detail, rings: rings) }) else { return }
        drawMesh(mesh)
    }

    /// 指定した寸法で平面を描画します。
    ///
    /// - Parameters:
    ///   - width: 平面の幅。
    ///   - height: 平面の高さ。
    public func plane(_ width: Float, _ height: Float) {
        let key = "plane_\(width)_\(height)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.plane(device: device, width: width, height: height) }) else { return }
        drawMesh(mesh)
    }

    /// 指定した半径、高さ、テッセレーション詳細度で円柱を描画します。
    ///
    /// - Parameters:
    ///   - radius: 円柱の半径。
    ///   - height: 円柱の高さ。
    ///   - detail: 放射方向のセグメント数。
    public func cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        let key = "cylinder_\(radius)_\(height)_\(detail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.cylinder(device: device, radius: radius, height: height, segments: detail) }) else { return }
        drawMesh(mesh)
    }

    /// 指定した半径、高さ、テッセレーション詳細度で円錐を描画します。
    ///
    /// - Parameters:
    ///   - radius: 底面の半径。
    ///   - height: 円錐の高さ。
    ///   - detail: 放射方向のセグメント数。
    public func cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24) {
        let key = "cone_\(radius)_\(height)_\(detail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.cone(device: device, radius: radius, height: height, segments: detail) }) else { return }
        drawMesh(mesh)
    }

    /// 指定したリング半径とチューブ半径でトーラスを描画します。
    ///
    /// - Parameters:
    ///   - ringRadius: トーラスの中心からチューブ中心までの距離。
    ///   - tubeRadius: チューブの半径。
    ///   - detail: リング周囲の放射方向セグメント数。
    public func torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24) {
        let tubeDetail = max(detail / 2, 8)
        let key = "torus_\(ringRadius)_\(tubeRadius)_\(detail)_\(tubeDetail)"
        guard let mesh = cachedMesh(key: key, create: { try Mesh.torus(device: device, ringRadius: ringRadius, tubeRadius: tubeRadius, segments: detail, tubeSegments: tubeDetail) }) else { return }
        drawMesh(mesh)
    }

    /// キャッシュ済みメッシュを検索または生成します。失敗時はエラーをログ出力します。
    private func cachedMesh(key: String, create: () throws -> Mesh) -> Mesh? {
        if var cached = meshCache[key] {
            cached.lastUsedFrame = meshCacheFrameCounter
            meshCache[key] = cached
            return cached.mesh
        }
        do {
            let mesh = try create()
            meshCache[key] = CachedMesh(mesh: mesh, lastUsedFrame: meshCacheFrameCounter)
            if meshCache.count > Self.maxMeshCacheSize {
                evictStaleMeshes()
            }
            return mesh
        } catch {
            print("[metaphor] Failed to create mesh '\(key)': \(error)")
            return nil
        }
    }

    /// メッシュキャッシュの最も古い半分を削除します。
    private func evictStaleMeshes() {
        let sorted = meshCache.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
        let removeCount = meshCache.count - Self.maxMeshCacheSize / 2
        for (key, _) in sorted.prefix(removeCount) {
            meshCache.removeValue(forKey: key)
        }
    }

    /// ビルド済みメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するメッシュ。
    public func mesh(_ mesh: Mesh) { drawMesh(mesh) }

    /// 実行時の頂点変更に対応するダイナミックメッシュを描画します。
    ///
    /// - Parameter mesh: 描画するダイナミックメッシュ。
    public func dynamicMesh(_ mesh: DynamicMesh) {
        mesh.ensureBuffers()
        guard let encoder = encoder,
              let vb = mesh.vertexBuffer else { return }
        guard hasFill || hasStroke else { return }

        // DynamicMesh はインスタンシング対象外
        flushInstanceBatch()

        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setVertexBuffer(vb, offset: 0, index: 0)

        if hasFill {
            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: 0
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let ib = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
            }
        }

        if hasStroke {
            encoder.setTriangleFillMode(.lines)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let ib = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
            }

            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - 3D カスタムシェイプ (beginShape / endShape)

    /// 3D カスタムシェイプの頂点記録を開始します。
    ///
    /// - Parameter mode: シェイプのテッセレーションモード。
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape3D = true
        shapeMode3D = mode
        shapeVertices3D.removeAll(keepingCapacity: true)
        pendingNormal = nil
    }

    /// 指定位置に 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - z: z座標。
    public func vertex(_ x: Float, _ y: Float, _ z: Float) {
        guard isRecordingShape3D else { return }
        shapeVertices3D.append(Vertex3D(
            position: SIMD3(x, y, z),
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: fillColor
        ))
    }

    /// 頂点カラー付きの 3D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - z: z座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ z: Float, _ color: Color) {
        guard isRecordingShape3D else { return }
        shapeVertices3D.append(Vertex3D(
            position: SIMD3(x, y, z),
            normal: pendingNormal ?? SIMD3(0, 1, 0),
            color: color.simd
        ))
    }

    /// 以降の頂点に適用する法線ベクトルを設定します。
    ///
    /// - Parameters:
    ///   - nx: 法線のx成分。
    ///   - ny: 法線のy成分。
    ///   - nz: 法線のz成分。
    public func normal(_ nx: Float, _ ny: Float, _ nz: Float) {
        pendingNormal = SIMD3(nx, ny, nz)
    }

    /// 記録を終了して 3D シェイプを描画します。
    ///
    /// - Parameter close: シェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        guard isRecordingShape3D else { return }
        isRecordingShape3D = false

        guard !shapeVertices3D.isEmpty else { return }

        // polygon/triangles モードで法線が明示的に設定されていない場合、自動計算
        if pendingNormal == nil {
            autoComputeNormals()
        }

        switch shapeMode3D {
        case .polygon:
            drawShape3DPolygon(close: close)
        case .triangles:
            drawShape3DTriangles()
        case .triangleStrip:
            drawShape3DTriangleStrip()
        case .triangleFan:
            drawShape3DTriangleFan()
        case .points:
            drawShape3DPoints()
        case .lines:
            drawShape3DLines()
        }

        pendingNormal = nil
    }

    // MARK: - プライベート: 3D シェイプテッセレーション

    // 3頂点ごとに面法線を計算
    private func autoComputeNormals() {
        var i = 0
        while i + 2 < shapeVertices3D.count {
            let p0 = shapeVertices3D[i].position
            let p1 = shapeVertices3D[i + 1].position
            let p2 = shapeVertices3D[i + 2].position
            let edge1 = p1 - p0
            let edge2 = p2 - p0
            let n = simd_normalize(simd_cross(edge1, edge2))
            let safeN = n.x.isNaN ? SIMD3<Float>(0, 1, 0) : n
            shapeVertices3D[i].normal = safeN
            shapeVertices3D[i + 1].normal = safeN
            shapeVertices3D[i + 2].normal = safeN
            i += 3
        }
    }

    // テッセレーション済み 3D 頂点配列を塗りつぶし・ワイヤーフレームパスで描画
    private func drawShape3DVertices(_ vertices: [Vertex3D]) {
        guard let encoder = encoder, !vertices.isEmpty else { return }
        guard hasFill || hasStroke else { return }

        // beginShape/endShape は個別頂点描画を使用するため、インスタンスバッチをフラッシュ
        flushInstanceBatch()

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if hasFill {
            encoder.setRenderPipelineState(pipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: 0
            )

            encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex3D>.stride * vertices.count, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        if hasStroke {
            encoder.setTriangleFillMode(.lines)
            encoder.setRenderPipelineState(pipelineState)
            if let depthState = depthState {
                encoder.setDepthStencilState(depthState)
            }
            encoder.setFrontFacing(.counterClockwise)
            encoder.setCullMode(.none)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex3D>.stride * vertices.count, index: 0)
            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            encoder.setTriangleFillMode(.fill)
        }
    }

    // 単純な三角形ファンでポリゴンをテッセレーション（凸ポリゴン向け）
    private func drawShape3DPolygon(close: CloseMode) {
        guard shapeVertices3D.count >= 3 else { return }

        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        // 最初の3頂点から面法線を計算
        let p0 = shapeVertices3D[0].position
        let p1 = shapeVertices3D[1].position
        let p2 = shapeVertices3D[2].position
        let faceNormal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
        let safeNormal = faceNormal.x.isNaN ? SIMD3<Float>(0, 1, 0) : faceNormal

        for i in 1..<(shapeVertices3D.count - 1) {
            var v0 = shapeVertices3D[0]
            var v1 = shapeVertices3D[i]
            var v2 = shapeVertices3D[i + 1]
            // 明示的な法線がない頂点に面法線を適用
            if pendingNormal == nil {
                v0.normal = safeNormal
                v1.normal = safeNormal
                v2.normal = safeNormal
            }
            triangulated.append(v0)
            triangulated.append(v1)
            triangulated.append(v2)
        }

        drawShape3DVertices(triangulated)
    }

    // 独立した三角形として頂点を直接描画（3頂点ごとに1つの三角形）
    private func drawShape3DTriangles() {
        let count = (shapeVertices3D.count / 3) * 3
        guard count >= 3 else { return }
        drawShape3DVertices(Array(shapeVertices3D.prefix(count)))
    }

    // 三角形ストリップを独立した三角形にテッセレーション
    private func drawShape3DTriangleStrip() {
        guard shapeVertices3D.count >= 3 else { return }
        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        for i in 0..<(shapeVertices3D.count - 2) {
            if i % 2 == 0 {
                triangulated.append(shapeVertices3D[i])
                triangulated.append(shapeVertices3D[i + 1])
                triangulated.append(shapeVertices3D[i + 2])
            } else {
                triangulated.append(shapeVertices3D[i + 1])
                triangulated.append(shapeVertices3D[i])
                triangulated.append(shapeVertices3D[i + 2])
            }
        }
        drawShape3DVertices(triangulated)
    }

    // 三角形ファンを独立した三角形にテッセレーション
    private func drawShape3DTriangleFan() {
        guard shapeVertices3D.count >= 3 else { return }
        var triangulated: [Vertex3D] = []
        triangulated.reserveCapacity((shapeVertices3D.count - 2) * 3)

        for i in 1..<(shapeVertices3D.count - 1) {
            triangulated.append(shapeVertices3D[0])
            triangulated.append(shapeVertices3D[i])
            triangulated.append(shapeVertices3D[i + 1])
        }
        drawShape3DVertices(triangulated)
    }

    // 各頂点を小さな三角形として描画し、ポイントをシミュレート
    private func drawShape3DPoints() {
        guard let encoder = encoder else { return }
        guard !shapeVertices3D.isEmpty else { return }

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)

        // すべての頂点の三角形を単一バッチで構築
        var allVerts: [Vertex3D] = []
        allVerts.reserveCapacity(shapeVertices3D.count * 3)

        let s: Float = 0.5
        for v in shapeVertices3D {
            allVerts.append(Vertex3D(position: v.position + SIMD3(-s, -s, 0), normal: v.normal, color: v.color))
            allVerts.append(Vertex3D(position: v.position + SIMD3( s, -s, 0), normal: v.normal, color: v.color))
            allVerts.append(Vertex3D(position: v.position + SIMD3( 0,  s, 0), normal: v.normal, color: v.color))
        }

        var uniforms = Canvas3DUniforms(
            modelMatrix: currentTransform,
            viewProjectionMatrix: viewProj,
            normalMatrix: normalMatrix,
            color: shapeVertices3D[0].color,
            cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
            time: currentTime,
            lightCount: 0,
            hasTexture: 0
        )

        encoder.setVertexBytes(allVerts, length: MemoryLayout<Vertex3D>.stride * allVerts.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

        var dummy = Light3D.zero
        encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
        var mat = currentMaterial
        encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: allVerts.count)
    }

    // 線分を細い三角形ペアとして描画（セグメントあたり2頂点）
    private func drawShape3DLines() {
        guard shapeVertices3D.count >= 2 else { return }
        var lineVerts: [Vertex3D] = []
        lineVerts.reserveCapacity((shapeVertices3D.count / 2) * 6)

        let lineWidth: Float = 0.5
        var i = 0
        while i + 1 < shapeVertices3D.count {
            let p0 = shapeVertices3D[i].position
            let p1 = shapeVertices3D[i + 1].position
            let dir = p1 - p0
            let len = simd_length(dir)
            guard len > 0 else { i += 2; continue }

            // 線方向とビュー方向の外積を使用してオフセットを計算
            let viewDir = simd_normalize(cameraEye - (p0 + p1) * 0.5)
            var offset = simd_normalize(simd_cross(dir, viewDir)) * lineWidth * 0.5
            if offset.x.isNaN { offset = SIMD3(0, lineWidth * 0.5, 0) }

            let n = shapeVertices3D[i].normal
            let c = shapeVertices3D[i].color

            lineVerts.append(Vertex3D(position: p0 + offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p0 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 + offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p0 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 - offset, normal: n, color: c))
            lineVerts.append(Vertex3D(position: p1 + offset, normal: n, color: c))
            i += 2
        }

        drawShape3DVertices(lineVerts)
    }

    // MARK: - 内部描画

    // インスタンシングパスまたはイミディエイトフォールバックを通してメッシュ描画をルーティング
    private func drawMesh(_ mesh: Mesh) {
        guard encoder != nil else { return }
        guard hasFill || hasStroke else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        // シャドウ有効時、シャドウパス用にドローコールを記録
        if shadowMap != nil {
            recordedDrawCalls.append(DrawCall3D(
                mesh: mesh,
                transform: currentTransform,
                fillColor: fillColor,
                material: currentMaterial,
                customMaterial: currentCustomMaterial,
                texture: currentTexture,
                isTextured: isTextured,
                hasFill: hasFill,
                hasStroke: hasStroke,
                strokeColor: strokeColor
            ))
        }

        // カスタム頂点シェーダーはインスタンシング不可; イミディエイトパスにフォールバック
        if let customMat = currentCustomMaterial, customMat.vertexFunction != nil {
            flushInstanceBatch()
            drawMeshImmediate(mesh)
            return
        }

        // バッチキーを生成
        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let key = BatchKey3D(
            meshID: ObjectIdentifier(mesh),
            isTextured: isTextured,
            textureID: currentTexture.map { ObjectIdentifier($0 as AnyObject) },
            material: currentMaterial,
            customMaterialID: currentCustomMaterial.map { ObjectIdentifier($0) },
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor
        )

        // インスタンスバッチへの蓄積を試みる
        if !instanceBatcher.tryAddInstance(
            key: key,
            mesh: mesh,
            texture: currentTexture,
            material: currentMaterial,
            customMaterial: currentCustomMaterial,
            hasFill: hasFill,
            hasStroke: hasStroke,
            strokeColor: strokeColor,
            transform: currentTransform,
            normalMatrix: normalMatrix,
            color: fillColor
        ) {
            // キー不一致またはバッファ満杯; 現在のバッチをフラッシュしてリトライ
            flushInstanceBatch()
            let _ = instanceBatcher.tryAddInstance(
                key: key,
                mesh: mesh,
                texture: currentTexture,
                material: currentMaterial,
                customMaterial: currentCustomMaterial,
                hasFill: hasFill,
                hasStroke: hasStroke,
                strokeColor: strokeColor,
                transform: currentTransform,
                normalMatrix: normalMatrix,
                color: fillColor
            )
        }
    }

    // MARK: - インスタンスバッチフラッシュ

    /// 蓄積されたインスタンスを単一のインスタンス描画コールとしてフラッシュします。
    private func flushInstanceBatch() {
        guard let encoder = encoder,
              instanceBatcher.instanceCount > 0,
              let mesh = instanceBatcher.currentMesh else { return }

        let isTextured = instanceBatcher.currentBatchKey?.isTextured ?? false
        let batchHasFill = instanceBatcher.currentHasFill
        let batchHasStroke = instanceBatcher.currentHasStroke

        // パイプラインを選択
        if let customMat = instanceBatcher.currentCustomMaterial,
           let customPipeline = getCustomPipeline(fragmentFunction: customMat.fragmentFunction, isTextured: isTextured) {
            encoder.setRenderPipelineState(customPipeline)
        } else {
            encoder.setRenderPipelineState(isTextured ? instancedTexturedPipelineState : instancedPipelineState)
        }

        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        // 頂点バッファ
        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // インスタンスバッファを buffer(6) に設定
        encoder.setVertexBuffer(instanceBatcher.currentBuffer, offset: instanceBatcher.currentBufferOffset, index: 6)

        // --- 塗りつぶしパス ---
        if batchHasFill {
            var sceneUniforms = InstancedSceneUniforms(
                viewProjectionMatrix: computeViewProjection(),
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: isTextured ? 1 : 0
            )
            encoder.setVertexBytes(&sceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)

            // ライト
            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            // マテリアル
            var mat = instanceBatcher.currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            // カスタムマテリアルパラメータ
            if let customMat = instanceBatcher.currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
            }

            // シャドウ
            if let shadow = shadowMap {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: shadow.lightSpaceMatrix,
                    shadowBias: shadow.shadowBias,
                    shadowEnabled: 1.0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
            } else {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: .identity,
                    shadowBias: 0,
                    shadowEnabled: 0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                if let dummy = dummyShadowTexture {
                    encoder.setFragmentTexture(dummy, index: 1)
                }
            }

            // テクスチャ
            if isTextured, let tex = instanceBatcher.currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            // インスタンス描画
            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: 0, instanceCount: instanceBatcher.instanceCount
                )
            } else {
                let vc = isTextured ? mesh.uvVertexCount : mesh.vertexCount
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: vc,
                    instanceCount: instanceBatcher.instanceCount
                )
            }
        }

        // --- ワイヤーフレーム（ストローク）パス ---
        if batchHasStroke {
            encoder.setTriangleFillMode(.lines)
            encoder.setRenderPipelineState(instancedPipelineState)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)

            // ワイヤーフレームはライティングなし。ストローク色は全インスタンスで統一
            // （BatchKey が同一 strokeColor を要求するため、全インスタンスが同じ値を共有）。
            // ストローク用にインスタンスバッファの色を上書きする代わりに、
            // シーンユニフォームで lightCount=0 とし、インスタンスの色をそのまま使用します。
            var wireSceneUniforms = InstancedSceneUniforms(
                viewProjectionMatrix: computeViewProjection(),
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )
            encoder.setVertexBytes(&wireSceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireSceneUniforms, length: MemoryLayout<InstancedSceneUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            var mat = instanceBatcher.currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            // ワイヤーフレームではシャドウ無効
            var shadowOff = ShadowFragmentUniforms(lightSpaceMatrix: .identity, shadowBias: 0, shadowEnabled: 0)
            encoder.setFragmentBytes(&shadowOff, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
            if let dummyTex = dummyShadowTexture {
                encoder.setFragmentTexture(dummyTex, index: 1)
            }

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: 0, instanceCount: instanceBatcher.instanceCount
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount,
                    instanceCount: instanceBatcher.instanceCount
                )
            }

            encoder.setTriangleFillMode(.fill)
        }

        instanceBatcher.reset()
    }

    // MARK: - イミディエイト描画（フォールバック、非インスタンス）

    // インスタンシングなしでメッシュを描画（カスタム頂点シェーダー用フォールバック）
    private func drawMeshImmediate(_ mesh: Mesh) {
        guard let encoder = encoder else { return }

        let isTextured = currentTexture != nil && mesh.hasUVs

        if let customMat = currentCustomMaterial,
           let customPipeline = getCustomPipeline(fragmentFunction: customMat.fragmentFunction, isTextured: isTextured, customVertexFunction: customMat.vertexFunction) {
            encoder.setRenderPipelineState(customPipeline)
        } else {
            encoder.setRenderPipelineState(isTextured ? texturedPipelineState : pipelineState)
        }
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)

        let normalMatrix = computeNormalMatrix(from: currentTransform)
        let viewProj = computeViewProjection()

        if isTextured, let uvBuffer = mesh.uvVertexBuffer {
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 0)
        } else {
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        }

        // --- 塗りつぶしパス ---
        if hasFill {
            var uniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: fillColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: UInt32(lightArray.count),
                hasTexture: isTextured ? 1 : 0
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            if lightArray.isEmpty {
                var dummy = Light3D.zero
                encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)
            } else {
                lightArray.withUnsafeBufferPointer { ptr in
                    encoder.setFragmentBytes(ptr.baseAddress!, length: ptr.count * MemoryLayout<Light3D>.stride, index: 2)
                }
            }

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let customMat = currentCustomMaterial, var params = customMat.parameters, !params.isEmpty {
                encoder.setFragmentBytes(&params, length: params.count, index: 4)
            }

            if let shadow = shadowMap {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: shadow.lightSpaceMatrix,
                    shadowBias: shadow.shadowBias,
                    shadowEnabled: 1.0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                encoder.setFragmentTexture(shadow.shadowTexture, index: 1)
            } else {
                var shadowUniforms = ShadowFragmentUniforms(
                    lightSpaceMatrix: .identity,
                    shadowBias: 0,
                    shadowEnabled: 0
                )
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowFragmentUniforms>.stride, index: 5)
                if let dummy = dummyShadowTexture {
                    encoder.setFragmentTexture(dummy, index: 1)
                }
            }

            if isTextured, let tex = currentTexture {
                encoder.setFragmentTexture(tex, index: 0)
            }

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0,
                    vertexCount: isTextured ? mesh.uvVertexCount : mesh.vertexCount
                )
            }
        }

        // --- ワイヤーフレーム（ストローク）パス ---
        if hasStroke {
            encoder.setTriangleFillMode(.lines)

            var wireUniforms = Canvas3DUniforms(
                modelMatrix: currentTransform,
                viewProjectionMatrix: viewProj,
                normalMatrix: normalMatrix,
                color: strokeColor,
                cameraPosition: SIMD4(cameraEye.x, cameraEye.y, cameraEye.z, 0),
                time: currentTime,
                lightCount: 0,
                hasTexture: 0
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&wireUniforms, length: MemoryLayout<Canvas3DUniforms>.stride, index: 1)

            var dummy = Light3D.zero
            encoder.setFragmentBytes(&dummy, length: MemoryLayout<Light3D>.stride, index: 2)

            var mat = currentMaterial
            encoder.setFragmentBytes(&mat, length: MemoryLayout<Material3D>.stride, index: 3)

            if let indexBuffer = mesh.indexBuffer, mesh.indexCount > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: mesh.indexCount,
                    indexType: mesh.indexType, indexBuffer: indexBuffer, indexBufferOffset: 0
                )
            } else {
                encoder.drawPrimitives(
                    type: .triangle, vertexStart: 0,
                    vertexCount: mesh.vertexCount
                )
            }

            encoder.setTriangleFillMode(.fill)
        }
    }

    // MARK: - カスタムパイプライン

    /// メッシュキャッシュをクリアし、キャッシュ済みの GPU メッシュバッファをすべて解放します。
    public func clearMeshCache() {
        meshCache.removeAll()
    }

    /// カスタムパイプラインキャッシュをクリアします。通常、シェーダーホットリロード後に呼び出します。
    public func clearCustomPipelineCache() {
        customPipelineCache.removeAll()
    }

    // キャッシュ済みカスタムシェーダーパイプラインを取得または生成
    private func getCustomPipeline(fragmentFunction: MTLFunction, isTextured: Bool, customVertexFunction: MTLFunction? = nil) -> MTLRenderPipelineState? {
        let vtxName = customVertexFunction?.name ?? "default"
        let cacheKey = "\(fragmentFunction.name)_\(vtxName)_\(isTextured)_\(sampleCount)"
        if let cached = customPipelineCache[cacheKey] {
            return cached
        }

        let vertexFn: MTLFunction?
        let layout: VertexLayout

        if let customVtx = customVertexFunction {
            vertexFn = customVtx
            layout = isTextured ? .positionNormalUV : .positionNormalColor
        } else if isTextured {
            vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.canvas3DTexturedVertex,
                from: ShaderLibrary.BuiltinKey.canvas3DTextured
            )
            layout = .positionNormalUV
        } else {
            vertexFn = shaderLibrary.function(
                named: BuiltinShaders.FunctionName.canvas3DVertex,
                from: ShaderLibrary.BuiltinKey.canvas3D
            )
            layout = .positionNormalColor
        }

        guard let pipeline = try? PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFunction)
            .vertexLayout(layout)
            .blending(.alpha)
            .sampleCount(sampleCount)
            .build()
        else {
            return nil
        }

        customPipelineCache[cacheKey] = pipeline
        if customPipelineCache.count > 32 {
            let keysToRemove = Array(customPipelineCache.keys).prefix(customPipelineCache.count - 16)
            for key in keysToRemove {
                customPipelineCache.removeValue(forKey: key)
            }
        }
        return pipeline
    }

    // MARK: - プライベートヘルパー

    // ビュー投影行列を計算してキャッシュ
    private func computeViewProjection() -> float4x4 {
        if viewProjectionDirty {
            let view = float4x4(lookAt: cameraEye, center: cameraCenter, up: cameraUp)
            let proj: float4x4
            if useOrthographic {
                proj = float4x4(
                    orthographic: orthoLeft, right: orthoRight,
                    bottom: orthoBottom, top: orthoTop,
                    near: nearPlane, far: farPlane
                )
            } else {
                let aspect = width / height
                proj = float4x4(perspectiveFov: fov, aspect: aspect, near: nearPlane, far: farPlane)
            }
            // Processing のY軸下向き規則（Canvas2D と同じ）に合わせてY軸を反転
            var flipY = float4x4(1)
            flipY.columns.1.y = -1
            cachedViewProjection = flipY * proj * view
            viewProjectionDirty = false
        }
        return cachedViewProjection
    }

    // モデル行列の左上 3x3 の逆転置から法線行列を計算
    private func computeNormalMatrix(from model: float4x4) -> float4x4 {
        let m3 = float3x3(
            SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z),
            SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z),
            SIMD3(model.columns.2.x, model.columns.2.y, model.columns.2.z)
        )
        let invT = m3.inverse.transpose
        return float4x4(columns: (
            SIMD4(invT.columns.0.x, invT.columns.0.y, invT.columns.0.z, 0),
            SIMD4(invT.columns.1.x, invT.columns.1.y, invT.columns.1.z, 0),
            SIMD4(invT.columns.2.x, invT.columns.2.y, invT.columns.2.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    // 最初のライト追加時にデフォルトのアンビエント値を設定
    private func ensureAmbientIfFirstLight() {
        if lightArray.isEmpty && !userSetAmbient {
            ambientColor = SIMD3(0.3, 0.3, 0.3)
            currentMaterial.ambientColor = SIMD4(0.3, 0.3, 0.3, 0)
        }
    }
}
