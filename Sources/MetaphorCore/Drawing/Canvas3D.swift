import Metal
import simd

// MARK: - Canvas3D

/// イミディエイトモード 3D 描画コンテキストを提供します。
///
/// p5.js WEBGL スタイルの API で 3D シーンを描画します。
/// Canvas2D と同じレンダーコマンドエンコーダーを共有し、3D 描画コマンドを即時実行します。
@MainActor
public final class Canvas3D: CanvasStyle {
    // 実装は関心事ごとに `Canvas3D+*.swift` へ分割されている（#439）。以下の状態は
    // それらの extension から参照するため `private` ではなく internal にしてある
    // （Swift の `private` は同一ファイル内の extension までしか届かない）。
    // モジュール外へは公開されない。

    // MARK: - Metal リソース

    let device: MTLDevice
    let shaderLibrary: ShaderLibrary
    let sampleCount: Int
    let pipelineState: MTLRenderPipelineState
    let texturedPipelineState: MTLRenderPipelineState
    /// ワイヤーフレーム（stroke）パス専用。頂点カラー（= 記録時の fill 色）を
    /// 無視して stroke 色だけで描く（#429）。
    let wirePipelineState: MTLRenderPipelineState
    let depthState: MTLDepthStencilState?
    let dummyShadowTexture: MTLTexture

    // インスタンスレンダリングパイプライン
    let instancedPipelineState: MTLRenderPipelineState
    let instancedTexturedPipelineState: MTLRenderPipelineState
    /// インスタンス描画のワイヤーフレーム（stroke）パス専用（#429）。
    let instancedWirePipelineState: MTLRenderPipelineState
    let instanceBatcher: InstanceBatcher3D

    static let maxLights = 8

    // MARK: - カスタムマテリアル状態

    var currentCustomMaterial: CustomMaterial?
    var customPipelineCache: [String: CachedPipeline] = [:]

    struct CachedPipeline {
        let pipeline: MTLRenderPipelineState
        var lastUsedFrame: Int
    }

    // MARK: - 寸法

    /// 3D キャンバスの幅（ポイント単位）。
    public let width: Float

    /// 3D キャンバスの高さ（ポイント単位）。
    public let height: Float

    // MARK: - フレームごとの状態

    var encoder: MTLRenderCommandEncoder?
    var currentTime: Float = 0

    /// beginShape/endShape の大型頂点列（setVertexBytes の 4096B 上限超過分）用の
    /// 永続トリプルバッファ。フレーム内はバンプ確保で詰め、フレーム境界でリング
    /// 回転する。以前はシェイプごとに使い捨て MTLBuffer を確保しており、毎フレーム
    /// 多数の大型シェイプを描くスケッチでアロケーションチャーンになっていた（#250）。
    let shapeVertexBuffer: GrowableGPUBuffer<Vertex3D>
    /// 現在のフレームのトリプルバッファインデックス（`begin()` で更新）。
    var shapeVertexBufferIndex = 0
    /// 現在のフレームで `shapeVertexBuffer` に書き込み済みの頂点数（バンプカーソル）。
    var shapeVertexBufferUsed = 0

    // MARK: - カメラ状態

    var cameraEye: SIMD3<Float> = SIMD3(0, 0, 5)
    var cameraCenter: SIMD3<Float> = .zero
    var cameraUp: SIMD3<Float> = SIMD3(0, 1, 0)
    static let defaultFov: Float = Float.pi / 3
    var fov: Float = Canvas3D.defaultFov
    var nearPlane: Float = 0.1
    var farPlane: Float = 10000
    var viewProjectionDirty: Bool = true
    var cachedViewProjection: float4x4 = .identity

    /// 記録経路で共有するカメラ/ライトのスナップショット（#201）。
    /// 状態が変わっていない間は同一インスタンスを DrawCall3D 間で共有する。
    var currentStateSnapshot: RenderStateSnapshot3D?

    var useOrthographic: Bool = false
    var orthoLeft: Float = 0
    var orthoRight: Float = 0
    var orthoBottom: Float = 0
    var orthoTop: Float = 0

    // MARK: - ライティング状態

    var lightArray: [Light3D] = []
    /// ライトが 1 つも無い間のアンビエント（無照明パスなので描画には出ない）。
    var ambientColor: SIMD3<Float> = SIMD3(0.2, 0.2, 0.2)
    var userSetAmbient: Bool = false

    /// `lights()` と「最初のライト追加時」に入る既定アンビエントの、
    /// `colorMode` のレンジに対する割合。
    ///
    /// 単位を `ambientLight()` と揃えるためにレンジ比で持つ。既定の
    /// `colorMode(.rgb, 255)` なら `ambientLight(0.3 * 255)` = `ambientLight(76.5)`
    /// と書いたのと同じ明るさになる（`ambientLight(0.3)` ではない点に注意）。
    static let defaultAmbientRatio: Float = 0.3

    // MARK: - マテリアル状態

    var currentMaterial: Material3D = .default

    // MARK: - テクスチャ状態

    var currentTexture: MTLTexture?

    // MARK: - 変換スタック

    struct StyleState3D {
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

    var stateStack: [StyleState3D] = []
    /// pushStyle()/popStyle() 用のスタイル専用スタック（transform は復元しない）。
    var styleOnlyStack: [StyleState3D] = []
    var matrixStack: [float4x4] = []
    var currentTransform: float4x4 = .identity

    // MARK: - スタイル

    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    public var hasFill: Bool = true
    public var hasStroke: Bool = false
    public var strokeColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    public var colorModeConfig: ColorModeConfig = ColorModeConfig()

    // MARK: - シェイプ構築状態（3D beginShape/endShape）

    var isRecordingShape3D: Bool = false
    var shapeMode3D: ShapeMode = .polygon
    var shapeVertices3D: [Vertex3D] = []
    /// 記録中の頂点 UV。`shapeVertices3D` と同じ添字で 1:1 に対応する（未指定の頂点は (0, 0)）。
    var shapeUVs3D: [SIMD2<Float>] = []
    /// このシェイプで `vertex(x, y, z, u, v)` が一度でも呼ばれたか。
    /// `texture()` と両方揃ったときだけテクスチャ経路へ入る。
    var shapeHasExplicitUV: Bool = false
    var pendingNormal: SIMD3<Float>?

    // MARK: - メッシュキャッシュ

    struct CachedMesh {
        let mesh: Mesh
        var lastUsedFrame: Int
    }

    var meshCache: [String: CachedMesh] = [:]

    /// テスト用: 現在のメッシュキャッシュのエントリ数。
    var meshCacheCountForTesting: Int { meshCache.count }
    var meshCacheFrameCounter: Int = 0
    static let maxMeshCacheSize = 64

    // MARK: - シャドウマッピング状態

    /// シャドウレンダリングに使用するシャドウマップ。シャドウ無効時は `nil`。
    var shadowMap: ShadowMap?

    /// 現在のフレームでシャドウ深度パス用に記録されたドローコール。
    var recordedDrawCalls: [DrawCall3D] = []

    /// `replayMainPass(encoder:)` 実行中かどうか。`true` の間、`drawMesh` は
    /// 記録をスキップして実際のメインパスエンコードを行う（記録済みコールの再生）。
    var isReplaying = false

    /// 再生開始時に退避した描画状態（`beginReplay`/`endReplay` で保存・復元）。
    var replaySaved: ReplaySavedState?

    /// 再生中に最後に適用したスナップショット（切替検出用、#201）。
    var lastReplaySnapshot: RenderStateSnapshot3D?

    /// 影に依存せずコマンド記録経路を有効化する opt-in フラグ（#71）。
    /// `METAPHOR_COMMAND_RECORD=1` で `SketchRunner` が立てる。既定は false（影オフは即時経路）。
    var commandRecordEnabled = false

    /// メインパスを「記録 → 再生」経路で処理すべきか（#71）。
    /// 影オン（同一フレームシャドウ）か、コマンド記録 opt-in のいずれかで true。
    /// `MetaphorRenderer.renderFrame()` の分岐と `drawMesh` の記録条件に使う。
    var shouldRecordMainPass: Bool { shadowMap != nil || commandRecordEnabled }

    /// draw() 内の呼び出し順を表す単調シーケンス番号の払い出し元（#71）。
    /// `SketchContext` がフレーム頭でリセットするカウンタを注入する。未注入時は 0。
    /// Canvas は Context を直接参照せず、このクロージャ経由でのみ seq を得る。
    var seqProvider: (() -> UInt32)?

    /// 3D を記録する直前に 2D の保留バッチを確定させるためのフック（#71・宿題①）。
    /// 2D はバッチを蓄積しフレーム末尾でフラッシュするため、3D 記録の直前に flush して
    /// 2D バッチの seq を「この 3D より前」に確定する。これにより呼び出し順が正しく保たれる。
    /// `SketchContext` が `canvas.flush()` を注入する。
    var flushPending2D: (() -> Void)?

    // MARK: - 初期化

    /// レンダラーからキャンバスを生成します。デバイス、シェーダーライブラリ、テクスチャサイズを継承します。
    ///
    /// - Parameter renderer: 設定の派生元となるレンダラー。
    /// - Throws: ``MetaphorError``。頂点・インスタンスバッファを確保できない場合は
    ///   ``MetaphorError/bufferCreationFailed(size:)``、描画パイプラインを作成できない
    ///   場合（組み込み 3D シェーダー関数が見つからない場合を含む）は
    ///   ``MetaphorError/pipelineCreationFailed(name:underlying:)``、ダミーシャドウ
    ///   テクスチャを作成できない場合は
    ///   ``MetaphorError/textureCreationFailed(width:height:format:)``。
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
    /// - Throws: ``MetaphorError``。頂点・インスタンスバッファを確保できない場合は
    ///   ``MetaphorError/bufferCreationFailed(size:)``、描画パイプラインを作成できない
    ///   場合（組み込み 3D シェーダー関数が見つからない場合を含む）は
    ///   ``MetaphorError/pipelineCreationFailed(name:underlying:)``、ダミーシャドウ
    ///   テクスチャを作成できない場合は
    ///   ``MetaphorError/textureCreationFailed(width:height:format:)``。
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

        // 大型シェイプ頂点用の拡張可能トリプルバッファ（Canvas2D の頂点バッファと
        // 同じ方式）。大型シェイプを使わないスケッチの常駐コストを抑えるため
        // 初期容量は小さく、必要に応じて倍増する
        self.shapeVertexBuffer = try GrowableGPUBuffer<Vertex3D>(
            device: device, initialCapacity: 256, maxCapacity: 1_000_000,
            label: "metaphor.canvas3D.shapeVertices"
        )

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

        // ワイヤーフレーム（stroke）パイプライン。フラグメントは共通（stroke は
        // ライティングなしで描くため lightCount=0 の分岐に入り in.color を返す）
        let wireVertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas3DWireVertex,
            from: ShaderLibrary.BuiltinKey.canvas3D
        )
        self.wirePipelineState = try PipelineFactory(device: device)
            .vertex(wireVertexFn)
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

        // インスタンスパイプライン（ワイヤーフレーム / stroke）
        let instWireVertexFn = shaderLibrary.function(
            named: Canvas3DInstancedShaders.wireVertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas3DInstanced
        )
        self.instancedWirePipelineState = try PipelineFactory(device: device)
            .vertex(instWireVertexFn)
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
        guard let dummyTex = device.makeTexture(descriptor: dummyDesc) else {
            throw MetaphorError.textureCreationFailed(width: 1, height: 1, format: "depth32Float")
        }
        self.dummyShadowTexture = dummyTex
    }

    // MARK: - プライベートヘルパー

    // ビュー投影行列を計算してキャッシュ
    func computeViewProjection() -> float4x4 {
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
    func computeNormalMatrix(from model: float4x4) -> float4x4 {
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
    func ensureAmbientIfFirstLight() {
        if lightArray.isEmpty && !userSetAmbient {
            applyDefaultAmbient()
        }
    }

    /// 既定アンビエントを適用する。
    ///
    /// `ambientLight()` とまったく同じ経路（`colorMode` のレンジ基準 → 正規化）を通すので、
    /// 「既定と同じ明るさにしたい」ときにユーザーが書くべき値が
    /// `ambientLight(Canvas3D.defaultAmbientRatio * <colorMode の最大値>)` だと読み取れる。
    /// 正規化後の値は `colorMode` 設定によらず `defaultAmbientRatio`（= 0.3）で不変。
    func applyDefaultAmbient() {
        let c = colorModeConfig.toGray(Canvas3D.defaultAmbientRatio * colorModeConfig.max1)
        ambientColor = SIMD3(c.r, c.g, c.b)
        currentMaterial.ambientColor = SIMD4(c.r, c.g, c.b, 0)
    }
}
