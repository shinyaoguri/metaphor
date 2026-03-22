import Metal
import simd

/// Metal を利用したイミディエイトモード 2D 描画コンテキストを提供します。
///
/// p5.js スタイルの API で Metal による 2D レンダリングを行います。
/// シェイプを事前確保された頂点バッファに蓄積し、``end()`` で一括描画します。
///
/// ```swift
/// let canvas = Canvas2D(renderer: renderer)
///
/// renderer.onDraw = { encoder, time in
///     canvas.begin(encoder: encoder)
///     canvas.background(.black)
///     canvas.fill(Color(hue: 0.6, saturation: 0.8, brightness: 1.0))
///     canvas.ellipse(960, 540, 300, 300)
///     canvas.end()
/// }
/// ```
@MainActor
public final class Canvas2D: CanvasStyle {
    // MARK: - Metal リソース

    let device: MTLDevice
    let shaderLibrary: ShaderLibrary
    let pipelineStates: [BlendMode: MTLRenderPipelineState]
    let texturedPipelineStates: [BlendMode: MTLRenderPipelineState]
    let depthStencilState: MTLDepthStencilState?

    // MARK: - 2D インスタンシングリソース

    let instancedPipelineStates: [BlendMode: MTLRenderPipelineState]
    let instanceBatcher2D: InstanceBatcher2D
    let unitCircleBuffer: MTLBuffer
    let unitCircleVertexCount: Int
    let unitRectBuffer: MTLBuffer
    let unitRectVertexCount: Int

    // CPU/GPU 同期競合を回避するトリプルバッファ
    private static let bufferCount = 3
    let colorBuffer: GrowableGPUBuffer<Vertex2D>
    let texturedBuffer: GrowableGPUBuffer<TexturedVertex2D>
    var currentBufferIndex: Int = 0

    var texturedVertexCount: Int = 0
    var texturedBufferOffset: Int = 0
    var currentBoundTexture: MTLTexture?

    // 現在のバッファの頂点ポインタ
    var vertices: UnsafeMutablePointer<Vertex2D> {
        colorBuffer.pointer(for: currentBufferIndex)
    }

    // 現在の頂点バッファ
    var vertexBuffer: MTLBuffer {
        colorBuffer.buffer(for: currentBufferIndex)
    }

    // 現在のテクスチャバッファの頂点ポインタ
    var texturedVertices: UnsafeMutablePointer<TexturedVertex2D> {
        texturedBuffer.pointer(for: currentBufferIndex)
    }

    // 現在のテクスチャ頂点バッファ
    private var texturedVertexBuffer: MTLBuffer {
        texturedBuffer.buffer(for: currentBufferIndex)
    }

    // MARK: - 寸法

    /// キャンバスの幅（ピクセル単位）。
    public let width: Float

    /// キャンバスの高さ（ピクセル単位）。
    public let height: Float

    // MARK: - 定数

    var maxVertices: Int { colorBuffer.capacity }
    var maxTexturedVertices: Int { texturedBuffer.capacity }
    let ellipseSegments: Int = 32

    // MARK: - フレームごとの状態

    var encoder: MTLRenderCommandEncoder?

    /// 現在のレンダーコマンドエンコーダーにアクセスします。フレーム中のみ有効です。
    public var currentEncoder: MTLRenderCommandEncoder? { encoder }
    var vertexCount: Int = 0
    var bufferOffset: Int = 0
    let projectionMatrix: float4x4

    // MARK: - スタイル状態

    public var fillColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    public var strokeColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var currentStrokeWeight: Float = 1.0
    public var hasFill: Bool = true
    public var hasStroke: Bool = true
    var currentBlendMode: BlendMode = .alpha
    var currentRectMode: RectMode = .corner
    var currentEllipseMode: EllipseMode = .center
    var currentImageMode: ImageMode = .corner
    public var colorModeConfig: ColorModeConfig = ColorModeConfig()
    var tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var hasTint: Bool = false
    var currentStrokeCap: StrokeCap = .round
    var currentStrokeJoin: StrokeJoin = .miter

    // MARK: - テキスト状態

    var currentTextSize: Float = 32
    var currentFontFamily: String = "Helvetica"
    var currentTextAlignH: TextAlignH = .left
    var currentTextAlignV: TextAlignV = .baseline
    var currentTextLeading: Float = 1.2
    let textRenderer: TextRenderer
    var frameCounter: Int = 0

    // MARK: - 曲線状態

    var curveDetailCount: Int = 20
    var curveTightnessValue: Float = 0.0

    // MARK: - シェイプ構築状態

    enum ShapeVertexType {
        case normal(Float, Float)
        case colored(Float, Float, SIMD4<Float>)
        case textured(Float, Float, Float, Float)
        case bezier(cx1: Float, cy1: Float, cx2: Float, cy2: Float, x: Float, y: Float)
        case curve(Float, Float)
    }

    var isRecordingShape: Bool = false
    var shapeMode: ShapeMode = .polygon
    var shapeVertexList: [ShapeVertexType] = {
        var arr: [ShapeVertexType] = []
        arr.reserveCapacity(64)
        return arr
    }()

    // MARK: - コンター状態（穴付きポリゴン用）

    var contourVertices: [[(Float, Float)]] = []
    var isRecordingContour: Bool = false
    var currentContour: [(Float, Float)] = []

    // MARK: - 背景最適化

    // 描画済みかどうかを追跡（background() の最適化用）
    var hasDrawnAnything: Bool = false

    /// 現在のフレームの draw() 中に background() が呼ばれたかどうか。
    /// 次のフレームの loadAction を決定するために使用されます。
    var backgroundCalledThisFrame: Bool = false

    /// 現在のフレームが Metal の loadAction でクリアされるかどうか。
    /// true の場合、まだ何も描画されていなければ background() はクワッド描画をスキップできます。
    var frameWillClear: Bool = true

    /// レンダーパスディスクリプタに現在のエンコーダー作成前にクリアカラーが
    /// 正常に適用されたかどうか。最初のフレームから Metal の loadAction = .clear
    /// を使用するため初期値は true です。全画面クワッドの頂点処理による
    /// サブピクセルラスタライゼーションのアーティファクトを回避します。
    /// デフォルトのレンダーパスクリアカラー（黒）は Processing のデフォルト背景と
    /// 一致するため、この最適化は一般的なケースで安全です。非デフォルトの背景色は
    /// onSetClearColor でキャプチャされ、次のフレームで有効になります。
    /// 詳細は SketchRunner の noLoop() 2フレームパスを参照してください。
    var clearColorApplied: Bool = true

    // クリアカラーを設定するクロージャ。MetaphorRenderer から注入される
    var onSetClearColor: ((Double, Double, Double, Double) -> Void)?

    // MARK: - スタイルスナップショット（push/pop 用）

    struct StyleState {
        var transform: float3x3
        var fillColor: SIMD4<Float>
        var strokeColor: SIMD4<Float>
        var strokeWeight: Float
        var hasFill: Bool
        var hasStroke: Bool
        var blendMode: BlendMode
        var rectMode: RectMode
        var ellipseMode: EllipseMode
        var imageMode: ImageMode
        var colorModeConfig: ColorModeConfig
        var tintColor: SIMD4<Float>
        var hasTint: Bool
        var textSize: Float
        var fontFamily: String
        var textAlignH: TextAlignH
        var textAlignV: TextAlignV
        var textLeading: Float
        var curveDetail: Int
        var curveTightness: Float
        var strokeCap: StrokeCap
        var strokeJoin: StrokeJoin
    }

    // MARK: - クリッピング状態

    private var clipRect: MTLScissorRect?
    private var clipStack: [MTLScissorRect?] = []

    // MARK: - 変換・スタイルスタック

    var stateStack: [StyleState] = []
    var styleOnlyStack: [StyleState] = []
    var matrixStack: [float3x3] = []
    var currentTransform: float3x3 = float3x3(1)

    // MARK: - 頂点レイアウト（パック済み、24バイト）

    struct Vertex2D {
        var posX: Float
        var posY: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    // MARK: - テクスチャ頂点レイアウト（パック済み、32バイト）

    struct TexturedVertex2D {
        var posX: Float
        var posY: Float
        var u: Float
        var v: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    // MARK: - 初期化

    /// ``MetaphorRenderer`` インスタンスからキャンバスを生成します。
    ///
    /// - Parameter renderer: Metal デバイス、シェーダーライブラリ、テクスチャサイズを提供するレンダラー。
    /// - Throws: バッファまたはパイプラインの生成に失敗した場合 ``MetaphorError``。
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

    /// 個別のコンポーネントからキャンバスを生成します。
    ///
    /// - Parameters:
    ///   - device: バッファとパイプラインの割り当てに使用する Metal デバイス。
    ///   - shaderLibrary: 組み込み 2D シェーダーを含むシェーダーライブラリ。
    ///   - depthStencilCache: 深度ステンシルステートを提供するキャッシュ。
    ///   - width: キャンバスの幅（ピクセル単位）。
    ///   - height: キャンバスの高さ（ピクセル単位）。
    ///   - sampleCount: パイプライン生成時の MSAA サンプル数。
    /// - Throws: バッファまたはパイプラインの生成に失敗した場合 ``MetaphorError``。
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
        self.width = width
        self.height = height

        // 拡張可能なトリプル頂点バッファ（小さく開始し、必要に応じて拡張）
        self.colorBuffer = try GrowableGPUBuffer<Vertex2D>(
            device: device, initialCapacity: 4096, maxCapacity: 1_000_000,
            label: "metaphor.canvas2D.color"
        )
        self.texturedBuffer = try GrowableGPUBuffer<TexturedVertex2D>(
            device: device, initialCapacity: 4096, maxCapacity: 1_000_000,
            label: "metaphor.canvas2D.textured"
        )

        // カラーパイプライン（BlendMode ごとに1つ）
        let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DVertex,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let diffFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DDifferenceFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let exclFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DExclusionFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )

        var colorPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let fragFn: MTLFunction?
            switch mode {
            case .difference: fragFn = diffFragFn
            case .exclusion: fragFn = exclFragFn
            default: fragFn = fragmentFn
            }
            colorPipelines[mode] = try PipelineFactory(device: device)
                .vertex(vertexFn)
                .fragment(fragFn)
                .vertexLayout(.position2DColor)
                .blending(mode)
                .sampleCount(sampleCount)
                .build()
        }
        self.pipelineStates = colorPipelines

        // テクスチャパイプライン（BlendMode ごとに1つ）
        let texVertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        let texFragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        let texDiffFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedDifferenceFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        let texExclFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedExclusionFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )

        var texPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let fragFn: MTLFunction?
            switch mode {
            case .difference: fragFn = texDiffFragFn
            case .exclusion: fragFn = texExclFragFn
            default: fragFn = texFragmentFn
            }
            texPipelines[mode] = try PipelineFactory(device: device)
                .vertex(texVertexFn)
                .fragment(fragFn)
                .vertexLayout(.position2DTexCoordColor)
                .blending(mode)
                .sampleCount(sampleCount)
                .build()
        }
        self.texturedPipelineStates = texPipelines

        // 深度テスト無効
        self.depthStencilState = depthStencilCache.state(for: .disabled)

        // テキストレンダラー
        self.textRenderer = TextRenderer(device: device)

        // 投影行列（左上原点、ピクセル座標）。
        // ハーフピクセルオフセット (1/w, -1/h) により整数座標がピクセル中心に
        // マッピングされます（例: canvas x=10 → viewport x=10.5）。
        // Metal のラスタライザはピクセル中心 (i+0.5, j+0.5) でカバレッジを
        // テストするため、このオフセットが必要です。これがないと、整数xでの
        // strokeWeight(1) ラインが1ピクセルをクリスプに塗りつぶす代わりに
        // 2ピクセルにまたがってしまいます。
        self.projectionMatrix = float4x4(columns: (
            SIMD4<Float>(2.0 / width, 0, 0, 0),
            SIMD4<Float>(0, -2.0 / height, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-1.0 + 1.0 / width, 1.0 - 1.0 / height, 0, 1)
        ))

        precondition(MemoryLayout<Vertex2D>.stride == 24,
                     "Vertex2D stride must be 24 to match position2DColor layout")
        precondition(MemoryLayout<TexturedVertex2D>.stride == 32,
                     "TexturedVertex2D stride must be 32 to match position2DTexCoordColor layout")

        // 2D インスタンシングリソース
        guard let (circleBuf, circleCount) = UnitMesh2D.createCircle(device: device) else {
            throw MetaphorError.bufferCreationFailed(size: 32 * 3 * MemoryLayout<SIMD2<Float>>.stride)
        }
        self.unitCircleBuffer = circleBuf
        self.unitCircleVertexCount = circleCount
        guard let (rectBuf, rectCount) = UnitMesh2D.createRect(device: device) else {
            throw MetaphorError.bufferCreationFailed(size: 6 * MemoryLayout<SIMD2<Float>>.stride)
        }
        self.unitRectBuffer = rectBuf
        self.unitRectVertexCount = rectCount
        self.instanceBatcher2D = try InstanceBatcher2D(device: device)

        // インスタンスパイプライン（BlendMode ごとに1つ）
        let instVertexFn = shaderLibrary.function(
            named: Canvas2DInstancedShaders.vertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas2DInstanced
        )
        var instPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let fragName: String
            switch mode {
            case .difference: fragName = Canvas2DInstancedShaders.differenceFragmentFunctionName
            case .exclusion: fragName = Canvas2DInstancedShaders.exclusionFragmentFunctionName
            default: fragName = Canvas2DInstancedShaders.fragmentFunctionName
            }
            let fragFn = shaderLibrary.function(
                named: fragName,
                from: ShaderLibrary.BuiltinKey.canvas2DInstanced
            )
            instPipelines[mode] = try PipelineFactory(device: device)
                .vertex(instVertexFn)
                .fragment(fragFn)
                .vertexLayout(.position2DOnly)
                .blending(mode)
                .sampleCount(sampleCount)
                .build()
        }
        self.instancedPipelineStates = instPipelines
    }

    // MARK: - フレーム制御

    /// 指定のレンダーコマンドエンコーダーで新しい描画フレームを開始します。
    ///
    /// 頂点数、スタイル、変換を含むすべてのフレームごとの状態をリセットします。
    /// 描画コマンドを発行する前に、各フレームの開始時に呼び出してください。
    ///
    /// - Parameters:
    ///   - encoder: 現在のフレームのレンダーコマンドエンコーダー。
    ///   - bufferIndex: このフレームのトリプルバッファインデックス。
    public func begin(encoder: MTLRenderCommandEncoder, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentBufferIndex = bufferIndex % Self.bufferCount
        // フレームごとのレンダリング状態をリセット
        self.vertexCount = 0
        self.bufferOffset = 0
        self.texturedVertexCount = 0
        self.texturedBufferOffset = 0
        self.currentBoundTexture = nil
        self.currentTransform = float3x3(1)
        self.stateStack.removeAll(keepingCapacity: true)
        // スタイル状態（fill、stroke、colorMode など）はフレーム間で保持される。
        // Processing の動作に合わせ、setup() のスタイルが draw() に引き継がれます。
        self.frameCounter += 1
        self.hasDrawnAnything = false
        self.backgroundCalledThisFrame = false
        self.instanceBatcher2D.beginFrame(bufferIndex: currentBufferIndex)
    }

    /// 蓄積されたすべての頂点をフラッシュし、エンコーダーを解放してフレームを終了します。
    public func end() {
        flush()
        // フレーム終了時にクリップ状態をリセット
        if clipRect != nil {
            clipRect = nil
            clipStack.removeAll(keepingCapacity: true)
        }
        encoder = nil
    }

    // MARK: - クリッピング

    /// 指定した矩形に後続の描画をクリッピングします。
    ///
    /// Metal のシザーテストによるハードウェアアクセラレーテッドクリッピングを使用します。
    /// ``endClip()`` を呼び出して前のクリップ領域を復元します。
    /// スタックによるネストされたクリップに対応しています。
    ///
    /// - Parameters:
    ///   - x: クリップ領域のx座標。
    ///   - y: クリップ領域のy座標。
    ///   - w: クリップ領域の幅。
    ///   - h: クリップ領域の高さ。
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        flush()
        clipStack.append(clipRect)
        let sx = max(0, Int(x))
        let sy = max(0, Int(y))
        let sw = max(0, min(Int(w), Int(width) - sx))
        let sh = max(0, min(Int(h), Int(height) - sy))
        clipRect = MTLScissorRect(x: sx, y: sy, width: sw, height: sh)
        encoder?.setScissorRect(clipRect!)
    }

    /// 現在のクリップ領域を終了し、前のクリップ領域を復元します。
    public func endClip() {
        flush()
        clipRect = clipStack.popLast() ?? nil
        if let rect = clipRect {
            encoder?.setScissorRect(rect)
        } else {
            // フルビューポートを復元
            let fullRect = MTLScissorRect(x: 0, y: 0, width: Int(width), height: Int(height))
            encoder?.setScissorRect(fullRect)
        }
    }

    /// カラー、テクスチャ、インスタンスを含むすべての保留中の描画バッチをフラッシュします。
    public func flush() {
        flushInstancedBatch()
        flushColorVertices()
        flushTexturedVertices()
    }

    // カラー頂点バッチのみをフラッシュ
    func flushColorVertices() {
        guard let encoder = encoder, vertexCount > 0 else { return }

        guard let pipeline = pipelineStates[currentBlendMode] else { return }
        encoder.setRenderPipelineState(pipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: bufferOffset, vertexCount: vertexCount)
        bufferOffset += vertexCount
        vertexCount = 0
    }

    // テクスチャ頂点バッチのみをフラッシュ
    func flushTexturedVertices() {
        guard let encoder = encoder, texturedVertexCount > 0 else { return }
        guard let texPipeline = texturedPipelineStates[currentBlendMode] else { return }
        guard let texture = currentBoundTexture else { return }

        encoder.setRenderPipelineState(texPipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(texturedVertexBuffer, offset: 0, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: texturedBufferOffset, vertexCount: texturedVertexCount)
        texturedBufferOffset += texturedVertexCount
        texturedVertexCount = 0
    }

    // MARK: - ブレンドモード

    /// ブレンドモードを設定します。切り替え前に現在のバッチをフラッシュします。
    ///
    /// - Parameter mode: 以降の描画コマンドに適用するブレンドモード。
    public func blendMode(_ mode: BlendMode) {
        if mode != currentBlendMode {
            flushInstancedBatch()
            flushColorVertices()
            flushTexturedVertices()
            currentBlendMode = mode
        }
    }

    // MARK: - シェイプモード設定

    /// 矩形の座標解釈モードを設定します。
    ///
    /// - Parameter mode: 矩形モード（例: `.corner`、`.center`）。
    public func rectMode(_ mode: RectMode) {
        currentRectMode = mode
    }

    /// 楕円の座標解釈モードを設定します。
    ///
    /// - Parameter mode: 楕円モード（例: `.center`、`.corner`）。
    public func ellipseMode(_ mode: EllipseMode) {
        currentEllipseMode = mode
    }

    /// 画像の座標解釈モードを設定します。
    ///
    /// - Parameter mode: 画像モード（例: `.corner`、`.center`）。
    public func imageMode(_ mode: ImageMode) {
        currentImageMode = mode
    }

    // MARK: - カラーモード

    // MARK: - ティント

    /// 画像のティント色を設定します。
    ///
    /// - Parameter color: 適用するティント色。
    public func tint(_ color: Color) {
        tintColor = color.simd
        hasTint = true
    }

    /// カラーモード値を使用して画像のティント色を設定します。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。現在のカラーモードに従って解釈されます。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        tintColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasTint = true
    }

    /// グレースケール値を使用してティント色を設定します。
    ///
    /// - Parameter gray: グレースケールの明度値。
    public func tint(_ gray: Float) {
        tintColor = colorModeConfig.toGray(gray).simd
        hasTint = true
    }

    /// グレースケールとアルファ値を使用してティント色を設定します。
    ///
    /// - Parameters:
    ///   - gray: グレースケールの明度値。
    ///   - alpha: アルファ透明度値。
    public func tint(_ gray: Float, _ alpha: Float) {
        tintColor = colorModeConfig.toGray(gray, alpha).simd
        hasTint = true
    }

    /// 画像のティントを無効にします。
    public func noTint() {
        tintColor = SIMD4<Float>(1, 1, 1, 1)
        hasTint = false
    }

    // MARK: - Canvas2D 固有のスタイル

    /// ストロークの太さ（線の太さ）をピクセル単位で設定します。
    ///
    /// - Parameter weight: ストロークの太さ。
    public func strokeWeight(_ weight: Float) {
        currentStrokeWeight = weight
    }

    /// 線の端点のストロークキャップスタイルを設定します。
    ///
    /// - Parameter cap: キャップスタイル（例: `.round`、`.square`、`.project`）。
    public func strokeCap(_ cap: StrokeCap) {
        currentStrokeCap = cap
    }

    /// 線の角のストロークジョインスタイルを設定します。
    ///
    /// - Parameter join: ジョインスタイル（例: `.miter`、`.bevel`、`.round`）。
    public func strokeJoin(_ join: StrokeJoin) {
        currentStrokeJoin = join
    }

    // MARK: - 背景

    /// 現在の変換を無視して、キャンバス全体を単色で塗りつぶします。
    ///
    /// このフレームでまだ何も描画されていない場合、最適なパフォーマンスのため
    /// クリアカラーの更新のみを行います。
    ///
    /// - Parameter color: 背景色。
    public func background(_ color: Color) {
        let c = color.simd
        backgroundCalledThisFrame = true
        onSetClearColor?(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
        if !hasDrawnAnything && frameWillClear && clearColorApplied {
            // Metal の loadAction = .clear がクリアを処理します。
            // 最初のフレームではこの最適化をスキップ: エンコーダーは
            // background() がクリアカラーを設定する前に作成されているため、
            // Metal のクリアは古いデフォルト（黒）を使用してしまいます。
            return
        }
        // 全画面クワッドを描画（既に何かが描画されているか、
        // loadAction = .load で明示的なクリアが必要な場合）。
        addVertexRaw(0, 0, c)
        addVertexRaw(width, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, height, c)
        flush()
    }

    /// グレースケール値で背景を塗りつぶします。
    ///
    /// - Parameter gray: グレースケールの明度値。
    public func background(_ gray: Float) {
        background(colorModeConfig.toGray(gray))
    }

    /// カラーモード値を使用して背景を塗りつぶします。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値。現在のカラーモードに従って解釈されます。
    ///   - v2: 第2カラーチャンネル値。
    ///   - v3: 第3カラーチャンネル値。
    ///   - a: オプションのアルファ値。
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        background(colorModeConfig.toColor(v1, v2, v3, a))
    }

    // MARK: - 2D インスタンスシェイプ描画

    // 現在のインスタンスバッチを GPU に送信
    func flushInstancedBatch() {
        guard let encoder = encoder,
              instanceBatcher2D.instanceCount > 0,
              let batchKey = instanceBatcher2D.currentBatchKey else { return }

        guard let pipeline = instancedPipelineStates[batchKey.blendMode] else { return }
        encoder.setRenderPipelineState(pipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)

        let (meshBuffer, meshVertexCount) = unitMeshFor(batchKey.shapeType)
        encoder.setVertexBuffer(meshBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBatcher2D.currentBuffer, offset: instanceBatcher2D.currentBufferOffset, index: 6)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: meshVertexCount,
            instanceCount: instanceBatcher2D.instanceCount
        )

        instanceBatcher2D.reset()
    }

    // シェイプをインスタンスバッチに追加。
    // cx, cy: ローカル空間での中心位置
    // sx, sy: 単位メッシュに適用するスケール係数
    func addShapeInstance(_ shapeType: Shape2DType, cx: Float, cy: Float, sx: Float, sy: Float) {
        hasDrawnAnything = true

        // 描画順序を保持: 保留中の非インスタンス頂点を先にフラッシュ
        if texturedVertexCount > 0 {
            flushTexturedVertices()
            currentBoundTexture = nil
        }
        if vertexCount > 0 {
            flushColorVertices()
        }

        let key = BatchKey2D(
            shapeType: shapeType,
            blendMode: currentBlendMode
        )

        // currentTransform * translate(cx,cy) * scale(sx,sy) を float4x4 に変換
        let shapeLocal = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(cx, cy, 1)
        ))
        let combined = currentTransform * shapeLocal
        let transform = Canvas2D.embed2DTransform(combined)

        if !instanceBatcher2D.tryAddInstance(key: key, transform: transform, color: fillColor) {
            flushInstancedBatch()
            if !instanceBatcher2D.tryAddInstance(key: key, transform: transform, color: fillColor) {
                // このフレームでインスタンスバッファが枯渇 — カラー頂点にフォールバック
                addShapeFallback(shapeType, cx: cx, cy: cy, sx: sx, sy: sy)
            }
        }
    }

    /// フォールバック: インスタンスバッファが満杯の場合、非インスタンスカラー頂点としてシェイプを描画します。
    private func addShapeFallback(_ shapeType: Shape2DType, cx: Float, cy: Float, sx: Float, sy: Float) {
        let color = fillColor
        switch shapeType {
        case .ellipse:
            let segments = 16
            let step = Float.pi * 2.0 / Float(segments)
            let rx = sx * 0.5
            let ry = sy * 0.5
            for i in 0..<segments {
                let a0 = step * Float(i)
                let a1 = step * Float(i + 1)
                addVertex(cx, cy, color)
                addVertex(cx + rx * cos(a0), cy + ry * sin(a0), color)
                addVertex(cx + rx * cos(a1), cy + ry * sin(a1), color)
            }
        case .rect:
            let hx = sx * 0.5
            let hy = sy * 0.5
            addVertex(cx - hx, cy - hy, color)
            addVertex(cx + hx, cy - hy, color)
            addVertex(cx + hx, cy + hy, color)
            addVertex(cx - hx, cy - hy, color)
            addVertex(cx + hx, cy + hy, color)
            addVertex(cx - hx, cy + hy, color)
        }
    }

    private func unitMeshFor(_ shapeType: Shape2DType) -> (MTLBuffer, Int) {
        switch shapeType {
        case .ellipse: return (unitCircleBuffer, unitCircleVertexCount)
        case .rect: return (unitRectBuffer, unitRectVertexCount)
        }
    }

    // MARK: - 変換スタック

    /// 現在の変換とスタイル状態をスタックに保存します。
    ///
    /// ``pop()`` で保存した状態を復元します。Processing API と互換です。
    public func push() {
        stateStack.append(StyleState(
            transform: currentTransform,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: currentStrokeWeight,
            hasFill: hasFill,
            hasStroke: hasStroke,
            blendMode: currentBlendMode,
            rectMode: currentRectMode,
            ellipseMode: currentEllipseMode,
            imageMode: currentImageMode,
            colorModeConfig: colorModeConfig,
            tintColor: tintColor,
            hasTint: hasTint,
            textSize: currentTextSize,
            fontFamily: currentFontFamily,
            textAlignH: currentTextAlignH,
            textAlignV: currentTextAlignV,
            textLeading: currentTextLeading,
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin
        ))
    }

    /// 直前に保存した変換とスタイル状態をスタックから復元します。
    ///
    /// ブレンドモードが変更された場合、現在のバッチをフラッシュします。Processing API と互換です。
    public func pop() {
        guard let saved = stateStack.popLast() else { return }
        let prevBlendMode = currentBlendMode
        currentTransform = saved.transform
        fillColor = saved.fillColor
        strokeColor = saved.strokeColor
        currentStrokeWeight = saved.strokeWeight
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        currentBlendMode = saved.blendMode
        currentRectMode = saved.rectMode
        currentEllipseMode = saved.ellipseMode
        currentImageMode = saved.imageMode
        colorModeConfig = saved.colorModeConfig
        tintColor = saved.tintColor
        hasTint = saved.hasTint
        currentTextSize = saved.textSize
        currentFontFamily = saved.fontFamily
        currentTextAlignH = saved.textAlignH
        currentTextAlignV = saved.textAlignV
        currentTextLeading = saved.textLeading
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        currentStrokeCap = saved.strokeCap
        currentStrokeJoin = saved.strokeJoin
        if prevBlendMode != currentBlendMode {
            flush()
        }
    }

    /// 変換を除くスタイル状態のみをスタイル専用スタックに保存します。
    public func pushStyle() {
        styleOnlyStack.append(StyleState(
            transform: currentTransform,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: currentStrokeWeight,
            hasFill: hasFill,
            hasStroke: hasStroke,
            blendMode: currentBlendMode,
            rectMode: currentRectMode,
            ellipseMode: currentEllipseMode,
            imageMode: currentImageMode,
            colorModeConfig: colorModeConfig,
            tintColor: tintColor,
            hasTint: hasTint,
            textSize: currentTextSize,
            fontFamily: currentFontFamily,
            textAlignH: currentTextAlignH,
            textAlignV: currentTextAlignV,
            textLeading: currentTextLeading,
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin
        ))
    }

    /// スタイル専用スタックからスタイル状態のみを復元します。変換は変更しません。
    public func popStyle() {
        guard let saved = styleOnlyStack.popLast() else { return }
        let prevBlendMode = currentBlendMode
        fillColor = saved.fillColor
        strokeColor = saved.strokeColor
        currentStrokeWeight = saved.strokeWeight
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        currentBlendMode = saved.blendMode
        currentRectMode = saved.rectMode
        currentEllipseMode = saved.ellipseMode
        currentImageMode = saved.imageMode
        colorModeConfig = saved.colorModeConfig
        tintColor = saved.tintColor
        hasTint = saved.hasTint
        currentTextSize = saved.textSize
        currentFontFamily = saved.fontFamily
        currentTextAlignH = saved.textAlignH
        currentTextAlignV = saved.textAlignV
        currentTextLeading = saved.textLeading
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        currentStrokeCap = saved.strokeCap
        currentStrokeJoin = saved.strokeJoin
        if prevBlendMode != currentBlendMode {
            flush()
        }
    }

    /// 現在の変換行列のみをマトリクススタックに保存します。
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// マトリクススタックから変換行列のみを復元します。
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// 現在の変換に平行移動を適用します。
    ///
    /// - Parameters:
    ///   - x: ピクセル単位の水平方向移動量。
    ///   - y: ピクセル単位の垂直方向移動量。
    public func translate(_ x: Float, _ y: Float) {
        let t = float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(x, y, 1)
        ))
        currentTransform = currentTransform * t
    }

    /// 現在の変換に回転を適用します。
    ///
    /// - Parameter angle: 回転角度（ラジアン）。
    public func rotate(_ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        let r = float3x3(columns: (
            SIMD3<Float>(c, s, 0),
            SIMD3<Float>(-s, c, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * r
    }

    /// 現在の変換に非均一スケールを適用します。
    ///
    /// - Parameters:
    ///   - sx: 水平方向のスケール係数。
    ///   - sy: 垂直方向のスケール係数。
    public func scale(_ sx: Float, _ sy: Float) {
        let s = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * s
    }

    /// 現在の変換に均一スケールを適用します。
    ///
    /// - Parameter s: 両軸に適用するスケール係数。
    public func scale(_ s: Float) {
        scale(s, s)
    }

    /// 現在の 2D 変換に指定した行列を乗算します。
    ///
    /// - Parameter matrix: 連結する 3x3 行列。
    public func applyMatrix(_ matrix: float3x3) {
        currentTransform = currentTransform * matrix
    }
}
