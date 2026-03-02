import Metal
import simd

/// Immediate-mode 2D描画コンテキスト
///
/// p5.js風のAPIでMetalの2D描画を行う。
/// 事前確保した頂点バッファに形状を蓄積し、`end()`で一括描画する。
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
public final class Canvas2D {
    // MARK: - Metal Resources

    let device: MTLDevice
    let shaderLibrary: ShaderLibrary
    let pipelineStates: [BlendMode: MTLRenderPipelineState]
    let texturedPipelineStates: [BlendMode: MTLRenderPipelineState]
    let depthStencilState: MTLDepthStencilState?

    /// トリプルバッファ (CPU/GPU同期競合を回避)
    private static let bufferCount = 3
    private let vertexBuffers: [MTLBuffer]
    private let verticesArray: [UnsafeMutablePointer<Vertex2D>]
    private var currentBufferIndex: Int = 0

    /// 現在のバッファの頂点ポインタ
    var vertices: UnsafeMutablePointer<Vertex2D> {
        verticesArray[currentBufferIndex]
    }

    /// 現在のバッファ
    var vertexBuffer: MTLBuffer {
        vertexBuffers[currentBufferIndex]
    }

    // MARK: - Dimensions

    /// キャンバスの幅（ピクセル）
    public let width: Float

    /// キャンバスの高さ（ピクセル）
    public let height: Float

    // MARK: - Constants

    let maxVertices: Int = 131072
    let ellipseSegments: Int = 32

    // MARK: - Per-frame State

    var encoder: MTLRenderCommandEncoder?

    /// 現在のレンダーコマンドエンコーダ（フレーム中のみ有効、上級者向け）
    public var currentEncoder: MTLRenderCommandEncoder? { encoder }
    var vertexCount: Int = 0
    var bufferOffset: Int = 0
    let projectionMatrix: float4x4

    // MARK: - Style State

    var fillColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var strokeColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var currentStrokeWeight: Float = 1.0
    var hasFill: Bool = true
    var hasStroke: Bool = true
    var currentBlendMode: BlendMode = .alpha
    var currentRectMode: RectMode = .corner
    var currentEllipseMode: EllipseMode = .center
    var currentImageMode: ImageMode = .corner
    var colorModeConfig: ColorModeConfig = ColorModeConfig()
    var tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var hasTint: Bool = false
    var currentStrokeCap: StrokeCap = .round
    var currentStrokeJoin: StrokeJoin = .miter

    // MARK: - Text State

    var currentTextSize: Float = 32
    var currentFontFamily: String = "Helvetica"
    var currentTextAlignH: TextAlignH = .left
    var currentTextAlignV: TextAlignV = .baseline
    var currentTextLeading: Float = 1.2
    let textRenderer: TextRenderer
    var frameCounter: Int = 0

    // MARK: - Curve State

    var curveDetailCount: Int = 20
    var curveTightnessValue: Float = 0.0

    // MARK: - Shape Building State

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

    // MARK: - Contour State (穴あき多角形用)

    var contourVertices: [[(Float, Float)]] = []
    var isRecordingContour: Bool = false
    var currentContour: [(Float, Float)] = []

    // MARK: - Background Optimization

    /// 何か描画済みかどうか（background() の最適化用）
    var hasDrawnAnything: Bool = false

    /// clearColor を設定するクロージャ（MetaphorRenderer から注入）
    var onSetClearColor: ((Double, Double, Double, Double) -> Void)?

    // MARK: - Style Snapshot (push/pop用)

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

    // MARK: - Transform & Style Stack

    var stateStack: [StyleState] = []
    var styleOnlyStack: [StyleState] = []
    var matrixStack: [float3x3] = []
    var currentTransform: float3x3 = float3x3(1)

    // MARK: - Vertex Layout (packed, 24 bytes)

    struct Vertex2D {
        var posX: Float
        var posY: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    // MARK: - Textured Vertex Layout (packed, 32 bytes)

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

    // MARK: - Initialization

    /// MetaphorRendererから生成
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

    /// コンポーネントから生成
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

        // トリプル頂点バッファ（事前確保）
        let bufferSize = maxVertices * MemoryLayout<Vertex2D>.stride
        var buffers: [MTLBuffer] = []
        var pointers: [UnsafeMutablePointer<Vertex2D>] = []
        for _ in 0..<Self.bufferCount {
            guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                throw Canvas2DError.bufferCreationFailed
            }
            buffers.append(buffer)
            pointers.append(buffer.contents().bindMemory(to: Vertex2D.self, capacity: maxVertices))
        }
        self.vertexBuffers = buffers
        self.verticesArray = pointers

        // カラーパイプライン（全BlendMode分）
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

        // テクスチャパイプライン（全BlendMode分）
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

        // 射影行列（左上原点、ピクセル座標）
        self.projectionMatrix = float4x4(columns: (
            SIMD4<Float>(2.0 / width, 0, 0, 0),
            SIMD4<Float>(0, -2.0 / height, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-1, 1, 0, 1)
        ))

        assert(MemoryLayout<Vertex2D>.stride == 24,
               "Vertex2D stride must be 24 to match position2DColor layout")
        assert(MemoryLayout<TexturedVertex2D>.stride == 32,
               "TexturedVertex2D stride must be 32 to match position2DTexCoordColor layout")
    }

    // MARK: - Frame Control

    /// 描画開始。毎フレームencoderとバッファインデックスを渡す。
    public func begin(encoder: MTLRenderCommandEncoder, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentBufferIndex = bufferIndex % Self.bufferCount
        self.vertexCount = 0
        self.bufferOffset = 0
        self.currentTransform = float3x3(1)
        self.stateStack.removeAll(keepingCapacity: true)
        self.fillColor = SIMD4<Float>(1, 1, 1, 1)
        self.strokeColor = SIMD4<Float>(1, 1, 1, 1)
        self.currentStrokeWeight = 1.0
        self.hasFill = true
        self.hasStroke = true
        self.currentBlendMode = .alpha
        self.currentRectMode = .corner
        self.currentEllipseMode = .center
        self.currentImageMode = .corner
        self.colorModeConfig = ColorModeConfig()
        self.tintColor = SIMD4<Float>(1, 1, 1, 1)
        self.hasTint = false
        self.curveDetailCount = 20
        self.curveTightnessValue = 0.0
        self.currentStrokeCap = .round
        self.currentStrokeJoin = .miter
        self.currentTextSize = 32
        self.currentFontFamily = "Helvetica"
        self.currentTextAlignH = .left
        self.currentTextAlignV = .baseline
        self.currentTextLeading = 1.2
        self.frameCounter += 1
        self.hasDrawnAnything = false
    }

    /// 蓄積した頂点を描画して終了
    public func end() {
        flush()
        encoder = nil
    }

    /// 蓄積した頂点を描画（バッファをリセット）
    public func flush() {
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

    // MARK: - Blend Mode

    /// ブレンドモードを変更（現在のバッチをフラッシュしてからスイッチ）
    public func blendMode(_ mode: BlendMode) {
        if mode != currentBlendMode {
            flush()
            currentBlendMode = mode
        }
    }

    // MARK: - Shape Mode Settings

    /// 矩形の座標解釈モードを設定
    public func rectMode(_ mode: RectMode) {
        currentRectMode = mode
    }

    /// 楕円の座標解釈モードを設定
    public func ellipseMode(_ mode: EllipseMode) {
        currentEllipseMode = mode
    }

    /// 画像の座標解釈モードを設定
    public func imageMode(_ mode: ImageMode) {
        currentImageMode = mode
    }

    // MARK: - Color Mode

    /// 色空間と最大値を設定
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        colorModeConfig = ColorModeConfig(space: space, max1: max1, max2: max2, max3: max3, maxAlpha: maxA)
    }

    /// 色空間と均一な最大値を設定
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        colorModeConfig = ColorModeConfig(space: space, max1: maxAll, max2: maxAll, max3: maxAll, maxAlpha: maxAll)
    }

    // MARK: - Tint

    /// 画像のティント色を設定
    public func tint(_ color: Color) {
        tintColor = color.simd
        hasTint = true
    }

    /// 画像のティント色を設定（colorModeに従って解釈）
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        tintColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasTint = true
    }

    /// グレースケールでティント色を設定
    public func tint(_ gray: Float) {
        tintColor = colorModeConfig.toGray(gray).simd
        hasTint = true
    }

    /// グレースケール＋アルファでティント色を設定
    public func tint(_ gray: Float, _ alpha: Float) {
        tintColor = colorModeConfig.toGray(gray, alpha).simd
        hasTint = true
    }

    /// ティントを無効化
    public func noTint() {
        tintColor = SIMD4<Float>(1, 1, 1, 1)
        hasTint = false
    }

    // MARK: - Style Sync

    /// DrawingStyle から共通スタイルを同期
    public func syncStyle(_ style: DrawingStyle) {
        fillColor = style.fillColor
        strokeColor = style.strokeColor
        hasFill = style.hasFill
        hasStroke = style.hasStroke
        colorModeConfig = style.colorModeConfig
    }

    // MARK: - Style

    /// 塗りつぶし色を設定
    public func fill(_ color: Color) {
        fillColor = color.simd
        hasFill = true
    }

    /// 塗りつぶし色を設定（colorModeに従って解釈）
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        fillColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasFill = true
    }

    /// グレースケールで塗りつぶし色を設定
    public func fill(_ gray: Float) {
        fillColor = colorModeConfig.toGray(gray).simd
        hasFill = true
    }

    /// グレースケール＋アルファで塗りつぶし色を設定
    public func fill(_ gray: Float, _ alpha: Float) {
        fillColor = colorModeConfig.toGray(gray, alpha).simd
        hasFill = true
    }

    /// 塗りつぶしなし
    public func noFill() {
        hasFill = false
    }

    /// 線の色を設定
    public func stroke(_ color: Color) {
        strokeColor = color.simd
        hasStroke = true
    }

    /// 線の色を設定（colorModeに従って解釈）
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        strokeColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasStroke = true
    }

    /// グレースケールで線の色を設定
    public func stroke(_ gray: Float) {
        strokeColor = colorModeConfig.toGray(gray).simd
        hasStroke = true
    }

    /// グレースケール＋アルファで線の色を設定
    public func stroke(_ gray: Float, _ alpha: Float) {
        strokeColor = colorModeConfig.toGray(gray, alpha).simd
        hasStroke = true
    }

    /// 線なし
    public func noStroke() {
        hasStroke = false
    }

    /// 線の太さを設定
    public func strokeWeight(_ weight: Float) {
        currentStrokeWeight = weight
    }

    /// ストロークの端点スタイルを設定
    public func strokeCap(_ cap: StrokeCap) {
        currentStrokeCap = cap
    }

    /// ストロークの接合スタイルを設定
    public func strokeJoin(_ join: StrokeJoin) {
        currentStrokeJoin = join
    }

    // MARK: - Background

    /// 背景を塗りつぶす（トランスフォーム無視）
    public func background(_ color: Color) {
        let c = color.simd
        onSetClearColor?(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
        if !hasDrawnAnything {
            return
        }
        addVertexRaw(0, 0, c)
        addVertexRaw(width, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, height, c)
        flush()
    }

    /// グレースケール背景
    public func background(_ gray: Float) {
        background(colorModeConfig.toGray(gray))
    }

    /// 背景色を設定（colorModeに従って解釈）
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        background(colorModeConfig.toColor(v1, v2, v3, a))
    }

    // MARK: - Transform Stack

    /// 現在のトランスフォームとスタイルを保存（Processing互換）
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

    /// 保存したトランスフォームとスタイルを復元（Processing互換）
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

    /// スタイル状態のみを保存（トランスフォームは含まない）
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

    /// スタイル状態のみを復元（トランスフォームはそのまま）
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

    /// トランスフォームのみを保存
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// トランスフォームのみを復元
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// 平行移動
    public func translate(_ x: Float, _ y: Float) {
        let t = float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(x, y, 1)
        ))
        currentTransform = currentTransform * t
    }

    /// 回転（ラジアン）
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

    /// スケール
    public func scale(_ sx: Float, _ sy: Float) {
        let s = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * s
    }

    /// 均一スケール
    public func scale(_ s: Float) {
        scale(s, s)
    }
}
