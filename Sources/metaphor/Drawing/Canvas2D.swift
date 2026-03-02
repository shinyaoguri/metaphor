import Metal
import simd

// MARK: - Rect / Ellipse / Image Mode

/// rect()の座標解釈モード
public enum RectMode: Sendable {
    /// x,y = 左上角、w,h = 幅と高さ（デフォルト）
    case corner
    /// x,y = 左上角、w,h = 右下角の座標
    case corners
    /// x,y = 中心、w,h = 幅と高さ
    case center
    /// x,y = 中心、w,h = 半幅と半高
    case radius
}

/// ellipse()の座標解釈モード
public enum EllipseMode: Sendable {
    /// x,y = 中心、w,h = 幅と高さ（デフォルト）
    case center
    /// x,y = 中心、w,h = 半径
    case radius
    /// x,y = 左上角、w,h = 幅と高さ
    case corner
    /// x,y = 左上角、w,h = 右下角の座標
    case corners
}

/// image()の座標解釈モード
public enum ImageMode: Sendable {
    /// x,y = 左上角（デフォルト）
    case corner
    /// x,y = 中心
    case center
    /// x,y = 左上角、w,h = 右下角の座標
    case corners
}

/// arc()の描画モード
public enum ArcMode: Sendable {
    /// 弧のみ（端点を接続しない）
    case open
    /// 端点間を直線で接続
    case chord
    /// 端点から中心への線（パイ型）
    case pie
}

// MARK: - Stroke Cap / Join

/// ストロークの端点スタイル
public enum StrokeCap: Sendable {
    /// 丸型（Processing デフォルト）
    case round
    /// 正方形（半strokeWeight分延長）
    case square
    /// 延長なし
    case butt
}

/// ストロークの接合スタイル
public enum StrokeJoin: Sendable {
    /// 鋭角接合（デフォルト）
    case miter
    /// 平面接合
    case bevel
    /// 円弧接合
    case round
}

// MARK: - Gradient Axis

/// グラデーションの方向
public enum GradientAxis: Sendable {
    /// 上から下
    case vertical
    /// 左から右
    case horizontal
    /// 左上から右下
    case diagonal
}

// MARK: - Shape Mode

/// beginShape()で使用する形状モード
public enum ShapeMode: Sendable {
    /// 任意の多角形（デフォルト）
    case polygon
    /// 点の集合
    case points
    /// 線分のペア
    case lines
    /// 三角形の列（3頂点ずつ）
    case triangles
    /// トライアングルストリップ
    case triangleStrip
    /// トライアングルファン
    case triangleFan
}

/// endShape()で使用する閉じモード
public enum CloseMode: Sendable {
    /// 形状を閉じない
    case open
    /// 最後の頂点と最初の頂点を接続して閉じる
    case close
}

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

    private let device: MTLDevice
    private let shaderLibrary: ShaderLibrary
    private let pipelineStates: [BlendMode: MTLRenderPipelineState]
    private let texturedPipelineStates: [BlendMode: MTLRenderPipelineState]
    private let depthStencilState: MTLDepthStencilState?

    /// トリプルバッファ (CPU/GPU同期競合を回避)
    private static let bufferCount = 3
    private let vertexBuffers: [MTLBuffer]
    private let verticesArray: [UnsafeMutablePointer<Vertex2D>]
    private var currentBufferIndex: Int = 0

    /// 現在のバッファの頂点ポインタ
    private var vertices: UnsafeMutablePointer<Vertex2D> {
        verticesArray[currentBufferIndex]
    }

    /// 現在のバッファ
    private var vertexBuffer: MTLBuffer {
        vertexBuffers[currentBufferIndex]
    }

    // MARK: - Dimensions

    /// キャンバスの幅（ピクセル）
    public let width: Float

    /// キャンバスの高さ（ピクセル）
    public let height: Float

    // MARK: - Constants

    private let maxVertices: Int = 131072
    private let ellipseSegments: Int = 32

    // MARK: - Per-frame State

    private var encoder: MTLRenderCommandEncoder?

    /// 現在のレンダーコマンドエンコーダ（フレーム中のみ有効、上級者向け）
    public var currentEncoder: MTLRenderCommandEncoder? { encoder }
    private var vertexCount: Int = 0
    private var bufferOffset: Int = 0
    private let projectionMatrix: float4x4

    // MARK: - Style State

    private var fillColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    private var strokeColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    private var currentStrokeWeight: Float = 1.0
    private var hasFill: Bool = true
    private var hasStroke: Bool = true
    private var currentBlendMode: BlendMode = .alpha
    private var currentRectMode: RectMode = .corner
    private var currentEllipseMode: EllipseMode = .center
    private var currentImageMode: ImageMode = .corner
    private var colorModeConfig: ColorModeConfig = ColorModeConfig()
    private var tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    private var hasTint: Bool = false
    private var currentStrokeCap: StrokeCap = .round
    private var currentStrokeJoin: StrokeJoin = .miter

    // MARK: - Text State

    private var currentTextSize: Float = 32
    private var currentFontFamily: String = "Helvetica"
    private var currentTextAlignH: TextAlignH = .left
    private var currentTextAlignV: TextAlignV = .baseline
    private var currentTextLeading: Float = 1.2
    private let textRenderer: TextRenderer
    private var frameCounter: Int = 0

    // MARK: - Curve State

    private var curveDetailCount: Int = 20
    private var curveTightnessValue: Float = 0.0

    // MARK: - Shape Building State

    private enum ShapeVertexType {
        case normal(Float, Float)
        case colored(Float, Float, SIMD4<Float>)
        case textured(Float, Float, Float, Float)
        case bezier(cx1: Float, cy1: Float, cx2: Float, cy2: Float, x: Float, y: Float)
        case curve(Float, Float)
    }

    private var isRecordingShape: Bool = false
    private var shapeMode: ShapeMode = .polygon
    private var shapeVertexList: [ShapeVertexType] = {
        var arr: [ShapeVertexType] = []
        arr.reserveCapacity(64)
        return arr
    }()

    // MARK: - Contour State (穴あき多角形用)

    private var contourVertices: [[(Float, Float)]] = []
    private var isRecordingContour: Bool = false
    private var currentContour: [(Float, Float)] = []

    // MARK: - Background Optimization

    /// 何か描画済みかどうか（background() の最適化用）
    private var hasDrawnAnything: Bool = false

    /// clearColor を設定するクロージャ（MetaphorRenderer から注入）
    var onSetClearColor: ((Double, Double, Double, Double) -> Void)?

    // MARK: - Style Snapshot (push/pop用)

    private struct StyleState {
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

    private var stateStack: [StyleState] = []
    private var styleOnlyStack: [StyleState] = []
    private var matrixStack: [float3x3] = []
    private var currentTransform: float3x3 = float3x3(1)

    // MARK: - Vertex Layout (packed, 24 bytes)

    private struct Vertex2D {
        var posX: Float
        var posY: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    // MARK: - Textured Vertex Layout (packed, 32 bytes)

    private struct TexturedVertex2D {
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
    /// - Parameters:
    ///   - encoder: レンダーコマンドエンコーダ
    ///   - bufferIndex: トリプルバッファのインデックス（0-2）
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
        // render pass clear color を次フレーム用に更新
        onSetClearColor?(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
        if !hasDrawnAnything {
            // 描画開始前: render pass の clear で既にクリア済み（quad 不要）
            return
        }
        // 描画途中: 全画面 quad で上書き
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
        // ブレンドモードが変わった場合はフラッシュ
        if prevBlendMode != currentBlendMode {
            flush()
        }
    }

    /// スタイル状態のみを保存（トランスフォームは含まない）
    public func pushStyle() {
        styleOnlyStack.append(StyleState(
            transform: currentTransform,  // 復元時には使わない
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
        // トランスフォームは復元しない
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

    // MARK: - Shapes

    /// 矩形（座標解釈はrectModeに依存）
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        // RectModeに応じて左上角(rx, ry)と幅高(rw, rh)を算出
        let rx: Float, ry: Float, rw: Float, rh: Float
        switch currentRectMode {
        case .corner:
            rx = x; ry = y; rw = w; rh = h
        case .corners:
            rx = min(x, w); ry = min(y, h); rw = abs(w - x); rh = abs(h - y)
        case .center:
            rx = x - w / 2; ry = y - h / 2; rw = w; rh = h
        case .radius:
            rx = x - w; ry = y - h; rw = w * 2; rh = h * 2
        }
        if hasFill {
            addTriangle(rx, ry, rx + rw, ry, rx + rw, ry + rh, fillColor)
            addTriangle(rx, ry, rx + rw, ry + rh, rx, ry + rh, fillColor)
        }
        if hasStroke {
            strokePolyline([
                (rx, ry), (rx + rw, ry), (rx + rw, ry + rh), (rx, ry + rh)
            ], closed: true)
        }
    }

    /// 角丸矩形（均一コーナー半径）
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        rect(x, y, w, h, r, r, r, r)
    }

    /// 角丸矩形（コーナー別半径: tl=左上, tr=右上, br=右下, bl=左下）
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        // 全コーナーが0なら通常のrect
        if tl <= 0 && tr <= 0 && br <= 0 && bl <= 0 {
            rect(x, y, w, h)
            return
        }

        // RectModeに応じて左上角(rx, ry)と幅高(rw, rh)を算出
        let rx: Float, ry: Float, rw: Float, rh: Float
        switch currentRectMode {
        case .corner:
            rx = x; ry = y; rw = w; rh = h
        case .corners:
            rx = min(x, w); ry = min(y, h); rw = abs(w - x); rh = abs(h - y)
        case .center:
            rx = x - w / 2; ry = y - h / 2; rw = w; rh = h
        case .radius:
            rx = x - w; ry = y - h; rw = w * 2; rh = h * 2
        }

        // コーナー半径をクランプ
        let maxR = min(rw, rh) * 0.5
        let rtl = min(max(tl, 0), maxR)
        let rtr = min(max(tr, 0), maxR)
        let rbr = min(max(br, 0), maxR)
        let rbl = min(max(bl, 0), maxR)

        // 輪郭頂点を生成（時計回り、スクリーン座標系）
        let segments = 8
        var outline: [(Float, Float)] = []
        outline.reserveCapacity((segments + 1) * 4)

        // 左上コーナー: center (rx+rtl, ry+rtl), angle PI → 3PI/2
        for j in 0...segments {
            let a = Float.pi + Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rtl + rtl * cos(a), ry + rtl + rtl * sin(a)))
        }
        // 右上コーナー: center (rx+rw-rtr, ry+rtr), angle 3PI/2 → 2PI
        for j in 0...segments {
            let a = Float.pi * 1.5 + Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rw - rtr + rtr * cos(a), ry + rtr + rtr * sin(a)))
        }
        // 右下コーナー: center (rx+rw-rbr, ry+rh-rbr), angle 0 → PI/2
        for j in 0...segments {
            let a = Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rw - rbr + rbr * cos(a), ry + rh - rbr + rbr * sin(a)))
        }
        // 左下コーナー: center (rx+rbl, ry+rh-rbl), angle PI/2 → PI
        for j in 0...segments {
            let a = Float.pi * 0.5 + Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rbl + rbl * cos(a), ry + rh - rbl + rbl * sin(a)))
        }

        // 塗り: 重心からのfan tessellation
        if hasFill && outline.count >= 3 {
            let cx = rx + rw * 0.5
            let cy = ry + rh * 0.5
            for i in 0..<outline.count {
                let next = (i + 1) % outline.count
                addTriangle(cx, cy, outline[i].0, outline[i].1, outline[next].0, outline[next].1, fillColor)
            }
        }

        // ストローク: 輪郭をstrokePolylineで描画
        if hasStroke && outline.count >= 2 {
            strokePolyline(outline, closed: true)
        }
    }

    /// 矩形のショートカット（正方形）
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        rect(x, y, size, size)
    }

    /// 四辺形
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        if hasFill {
            addTriangle(x1, y1, x2, y2, x3, y3, fillColor)
            addTriangle(x1, y1, x3, y3, x4, y4, fillColor)
        }
        if hasStroke {
            strokeLine(x1, y1, x2, y2)
            strokeLine(x2, y2, x3, y3)
            strokeLine(x3, y3, x4, y4)
            strokeLine(x4, y4, x1, y1)
        }
    }

    // MARK: - Gradient

    /// 線形グラデーション矩形を描画
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        let sc1 = c1.simd
        let sc2 = c2.simd

        let tl: SIMD4<Float>, tr: SIMD4<Float>, bl: SIMD4<Float>, br: SIMD4<Float>
        switch axis {
        case .vertical:
            tl = sc1; tr = sc1; bl = sc2; br = sc2
        case .horizontal:
            tl = sc1; tr = sc2; bl = sc1; br = sc2
        case .diagonal:
            tl = sc1; tr = lerpSIMD(sc1, sc2, 0.5)
            bl = lerpSIMD(sc1, sc2, 0.5); br = sc2
        }

        // 2 triangles
        addVertex(x, y, tl)
        addVertex(x + w, y, tr)
        addVertex(x + w, y + h, br)

        addVertex(x, y, tl)
        addVertex(x + w, y + h, br)
        addVertex(x, y + h, bl)
    }

    /// 放射状グラデーションを描画
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        let sc1 = innerColor.simd
        let sc2 = outerColor.simd
        let segs = max(segments, 6)

        for i in 0..<segs {
            let a1 = Float(i) / Float(segs) * Float.pi * 2
            let a2 = Float(i + 1) / Float(segs) * Float.pi * 2

            let ex1 = cx + cos(a1) * radius
            let ey1 = cy + sin(a1) * radius
            let ex2 = cx + cos(a2) * radius
            let ey2 = cy + sin(a2) * radius

            addVertex(cx, cy, sc1)
            addVertex(ex1, ey1, sc2)
            addVertex(ex2, ey2, sc2)
        }
    }

    /// SIMD4 の線形補間（内部ヘルパー）
    private func lerpSIMD(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        a + (b - a) * t
    }

    /// 楕円（座標解釈はellipseModeに依存）
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        // EllipseModeに応じて中心(cx, cy)と半径(rx, ry)を算出
        let cx: Float, cy: Float, rx: Float, ry: Float
        switch currentEllipseMode {
        case .center:
            cx = x; cy = y; rx = w * 0.5; ry = h * 0.5
        case .radius:
            cx = x; cy = y; rx = w; ry = h
        case .corner:
            rx = w * 0.5; ry = h * 0.5; cx = x + rx; cy = y + ry
        case .corners:
            rx = abs(w - x) * 0.5; ry = abs(h - y) * 0.5
            cx = min(x, w) + rx; cy = min(y, h) + ry
        }
        let step = Float.pi * 2.0 / Float(ellipseSegments)

        if hasFill {
            for i in 0..<ellipseSegments {
                let a0 = step * Float(i)
                let a1 = step * Float(i + 1)
                let px0 = cx + rx * cos(a0)
                let py0 = cy + ry * sin(a0)
                let px1 = cx + rx * cos(a1)
                let py1 = cy + ry * sin(a1)
                addTriangle(cx, cy, px0, py0, px1, py1, fillColor)
            }
        }
        if hasStroke {
            for i in 0..<ellipseSegments {
                let a0 = step * Float(i)
                let a1 = step * Float(i + 1)
                let px0 = cx + rx * cos(a0)
                let py0 = cy + ry * sin(a0)
                let px1 = cx + rx * cos(a1)
                let py1 = cy + ry * sin(a1)
                strokeLine(px0, py0, px1, py1)
            }
        }
    }

    /// 円（ellipseの簡易版）
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        ellipse(x, y, diameter, diameter)
    }

    /// 直線
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        strokeLine(x1, y1, x2, y2)
    }

    /// 三角形
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        if hasFill {
            addTriangle(x1, y1, x2, y2, x3, y3, fillColor)
        }
        if hasStroke {
            strokeLine(x1, y1, x2, y2)
            strokeLine(x2, y2, x3, y3)
            strokeLine(x3, y3, x1, y1)
        }
    }

    /// 多角形（頂点配列）— 凹多角形対応
    public func polygon(_ points: [(Float, Float)]) {
        guard points.count >= 3 else { return }

        if hasFill {
            let indices = EarClipTriangulator.triangulate(points)
            var i = 0
            while i + 2 < indices.count {
                addTriangle(
                    points[indices[i]].0, points[indices[i]].1,
                    points[indices[i + 1]].0, points[indices[i + 1]].1,
                    points[indices[i + 2]].0, points[indices[i + 2]].1,
                    fillColor
                )
                i += 3
            }
        }
        if hasStroke {
            for i in 0..<points.count {
                let next = (i + 1) % points.count
                strokeLine(points[i].0, points[i].1, points[next].0, points[next].1)
            }
        }
    }

    /// 円弧 (startAngle, stopAngle はラジアン)
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        let rx = w * 0.5
        let ry = h * 0.5
        let arcLength = stopAngle - startAngle
        let segments = max(4, Int(Float(ellipseSegments) * abs(arcLength) / (Float.pi * 2)))
        let step = arcLength / Float(segments)

        if hasFill {
            for i in 0..<segments {
                let a0 = startAngle + step * Float(i)
                let a1 = startAngle + step * Float(i + 1)
                let px0 = x + rx * cos(a0)
                let py0 = y + ry * sin(a0)
                let px1 = x + rx * cos(a1)
                let py1 = y + ry * sin(a1)
                addTriangle(x, y, px0, py0, px1, py1, fillColor)
            }
        }
        if hasStroke {
            // 弧のストローク
            for i in 0..<segments {
                let a0 = startAngle + step * Float(i)
                let a1 = startAngle + step * Float(i + 1)
                let px0 = x + rx * cos(a0)
                let py0 = y + ry * sin(a0)
                let px1 = x + rx * cos(a1)
                let py1 = y + ry * sin(a1)
                strokeLine(px0, py0, px1, py1)
            }
            // モード別の追加ストローク
            let firstX = x + rx * cos(startAngle)
            let firstY = y + ry * sin(startAngle)
            let lastX = x + rx * cos(stopAngle)
            let lastY = y + ry * sin(stopAngle)
            switch mode {
            case .open:
                break
            case .chord:
                strokeLine(lastX, lastY, firstX, firstY)
            case .pie:
                strokeLine(firstX, firstY, x, y)
                strokeLine(x, y, lastX, lastY)
            }
        }
    }

    /// 3次ベジェ曲線
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        let segments = 24
        let step = 1.0 / Float(segments)

        var prevX = x1
        var prevY = y1

        for i in 1...segments {
            let t = step * Float(i)
            let u = 1 - t
            let px = u * u * u * x1 + 3 * u * u * t * cx1 + 3 * u * t * t * cx2 + t * t * t * x2
            let py = u * u * u * y1 + 3 * u * u * t * cy1 + 3 * u * t * t * cy2 + t * t * t * y2

            if hasStroke {
                strokeLine(prevX, prevY, px, py)
            }

            prevX = px
            prevY = py
        }
    }

    /// Catmull-Romスプライン曲線（4点: 制御点1, 開始点, 終了点, 制御点2）
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        guard hasStroke else { return }
        let segments = curveDetailCount
        var prevX = x2
        var prevY = y2

        for i in 1...segments {
            let t = Float(i) / Float(segments)
            let px = curvePoint(x1, x2, x3, x4, t)
            let py = curvePoint(y1, y2, y3, y4, t)
            strokeLine(prevX, prevY, px, py)
            prevX = px
            prevY = py
        }
    }

    /// 点（小さい円として描画）
    public func point(_ x: Float, _ y: Float) {
        let r = currentStrokeWeight * 0.5
        let saved = (hasFill, fillColor, hasStroke)
        hasFill = true
        fillColor = strokeColor
        hasStroke = false
        ellipse(x, y, r * 2, r * 2)
        hasFill = saved.0
        fillColor = saved.1
        hasStroke = saved.2
    }

    // MARK: - Image

    /// 画像を描画（元サイズ）
    public func image(_ img: MImage, _ x: Float, _ y: Float) {
        image(img, x, y, img.width, img.height)
    }

    /// 画像をサイズ指定で描画（座標解釈はimageModeに依存）
    public func image(_ img: MImage, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        let dx: Float, dy: Float, dw: Float, dh: Float
        switch currentImageMode {
        case .corner:
            dx = x; dy = y; dw = w; dh = h
        case .center:
            dx = x - w / 2; dy = y - h / 2; dw = w; dh = h
        case .corners:
            dx = min(x, w); dy = min(y, h); dw = abs(w - x); dh = abs(h - y)
        }
        drawTexturedQuad(texture: img.texture, x: dx, y: dy, w: dw, h: dh)
    }

    /// サブイメージ描画（スプライトシート/タイルマップ用）
    /// - Parameters:
    ///   - dx/dy/dw/dh: 描画先矩形
    ///   - sx/sy/sw/sh: ソース矩形（ピクセル単位）
    public func image(
        _ img: MImage,
        _ dx: Float, _ dy: Float, _ dw: Float, _ dh: Float,
        _ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float
    ) {
        drawTexturedQuad(
            texture: img.texture, x: dx, y: dy, w: dw, h: dh,
            srcX: sx, srcY: sy, srcW: sw, srcH: sh
        )
    }

    // MARK: - Text

    /// テキストサイズを設定
    public func textSize(_ size: Float) {
        currentTextSize = size
    }

    /// フォントを設定
    public func textFont(_ family: String) {
        currentFontFamily = family
    }

    /// テキスト揃えを設定
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        currentTextAlignH = horizontal
        currentTextAlignV = vertical
    }

    /// テキストの行間を設定（1.0=ぴったり、1.2=デフォルト）
    public func textLeading(_ leading: Float) {
        currentTextLeading = leading
    }

    /// テキストの描画幅を取得
    public func textWidth(_ string: String) -> Float {
        textRenderer.textWidth(string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// フォントのアセントを取得
    public func textAscent() -> Float {
        textRenderer.textAscent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// フォントのディセントを取得
    public func textDescent() -> Float {
        textRenderer.textDescent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// テキストを描画
    public func text(_ string: String, _ x: Float, _ y: Float) {
        guard !string.isEmpty else { return }

        // アトラスベースの高速パスを試行
        if let (atlasTex, glyphs) = textRenderer.textGlyphs(
            string: string, fontSize: currentTextSize, fontFamily: currentFontFamily
        ), !glyphs.isEmpty {
            // テキスト全体の幅と高さを計算
            let totalWidth = glyphs.last.map { $0.x + $0.width } ?? 0
            let ascent = textRenderer.textAscent(fontSize: currentTextSize, fontFamily: currentFontFamily)
            let descent = textRenderer.textDescent(fontSize: currentTextSize, fontFamily: currentFontFamily)
            let totalHeight = ascent + descent

            var drawX = x
            var drawY = y
            switch currentTextAlignH {
            case .left: break
            case .center: drawX -= totalWidth / 2
            case .right: drawX -= totalWidth
            }
            switch currentTextAlignV {
            case .top: break
            case .center: drawY -= totalHeight / 2
            case .baseline: drawY -= ascent
            case .bottom: drawY -= totalHeight
            }

            drawTextFromAtlas(texture: atlasTex, glyphs: glyphs, x: drawX, y: drawY)
            return
        }

        // フォールバック: 従来の per-string テクスチャ
        guard let cached = textRenderer.textTexture(
            string: string,
            fontSize: currentTextSize,
            fontFamily: currentFontFamily,
            frameCount: frameCounter
        ) else { return }

        var drawX = x
        var drawY = y
        switch currentTextAlignH {
        case .left: break
        case .center: drawX -= cached.width / 2
        case .right: drawX -= cached.width
        }
        switch currentTextAlignV {
        case .top: break
        case .center: drawY -= cached.height / 2
        case .baseline: drawY -= cached.height * 0.8
        case .bottom: drawY -= cached.height
        }

        drawTexturedQuad(texture: cached.texture, x: drawX, y: drawY, w: cached.width, h: cached.height)
    }

    /// ボックス内にテキストを描画（自動折り返し）
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        guard !string.isEmpty else { return }
        guard let cached = textRenderer.textTextureMultiline(
            string: string,
            fontSize: currentTextSize,
            fontFamily: currentFontFamily,
            maxWidth: w,
            maxHeight: h,
            leading: currentTextLeading,
            frameCount: frameCounter
        ) else { return }

        var drawX = x
        var drawY = y
        switch currentTextAlignH {
        case .left: break
        case .center: drawX += (w - cached.width) / 2
        case .right: drawX += w - cached.width
        }
        switch currentTextAlignV {
        case .top: break
        case .center: drawY += (h - cached.height) / 2
        case .baseline: drawY += (h - cached.height) * 0.8
        case .bottom: drawY += h - cached.height
        }

        drawTexturedQuad(texture: cached.texture, x: drawX, y: drawY, w: cached.width, h: cached.height)
    }

    // MARK: - Custom Shapes (beginShape / endShape)

    /// 頂点ベースの形状記録を開始
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape = true
        shapeMode = mode
        shapeVertexList.removeAll(keepingCapacity: true)
        contourVertices.removeAll(keepingCapacity: true)
        isRecordingContour = false
    }

    /// 形状に頂点を追加（beginShape〜endShape間で使用）
    public func vertex(_ x: Float, _ y: Float) {
        guard isRecordingShape else { return }
        if isRecordingContour {
            currentContour.append((x, y))
        } else {
            shapeVertexList.append(.normal(x, y))
        }
    }

    /// 頂点カラー付きで頂点を追加
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.colored(x, y, color.simd))
    }

    /// UV座標付きで頂点を追加（テクスチャマッピング用）
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.textured(x, y, u, v))
    }

    /// 3次ベジェ曲線の制御点と終点を追加（beginShape〜endShape間で使用）
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.bezier(cx1: cx1, cy1: cy1, cx2: cx2, cy2: cy2, x: x, y: y))
    }

    /// Catmull-Romスプラインの頂点を追加（beginShape〜endShape間で使用）
    public func curveVertex(_ x: Float, _ y: Float) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.curve(x, y))
    }

    /// コンター（穴）の記録を開始（beginShape〜endShape間で使用）
    public func beginContour() {
        guard isRecordingShape else { return }
        isRecordingContour = true
        currentContour.removeAll(keepingCapacity: true)
    }

    /// コンター（穴）の記録を終了
    public func endContour() {
        guard isRecordingContour else { return }
        isRecordingContour = false
        if currentContour.count >= 3 {
            contourVertices.append(currentContour)
        }
    }

    /// カーブの分割数を設定
    public func curveDetail(_ n: Int) {
        curveDetailCount = max(1, n)
    }

    /// カーブの張り具合を設定（-5.0〜5.0、0.0がCatmull-Rom）
    public func curveTightness(_ t: Float) {
        curveTightnessValue = t
    }

    /// 形状記録を終了してテッセレーション・描画
    public func endShape(_ close: CloseMode = .open) {
        guard isRecordingShape else { return }
        isRecordingShape = false

        guard !shapeVertexList.isEmpty else { return }

        // 頂点カラーまたはUVが含まれるか判定
        let hasPerVertexColor = shapeVertexList.contains { if case .colored = $0 { return true }; return false }
        let hasUV = shapeVertexList.contains { if case .textured = $0 { return true }; return false }

        if hasPerVertexColor || hasUV {
            // 拡張頂点パスを使用
            let exVerts = expandShapeVerticesEx()
            guard !exVerts.isEmpty else { return }

            switch shapeMode {
            case .polygon:
                drawPolygonShapeEx(exVerts, close: close)
            case .triangles:
                drawTrianglesShapeEx(exVerts)
            case .triangleStrip:
                drawTriangleStripShapeEx(exVerts)
            case .triangleFan:
                drawTriangleFanShapeEx(exVerts)
            case .points:
                drawPointsShape(exVerts.map { $0.tuple })
            case .lines:
                drawLinesShape(exVerts.map { $0.tuple })
            }
        } else {
            // 従来パス（高速）
            let verts = expandShapeVertices()
            guard !verts.isEmpty else { return }

            switch shapeMode {
            case .polygon:
                drawPolygonShape(verts, close: close)
            case .points:
                drawPointsShape(verts)
            case .lines:
                drawLinesShape(verts)
            case .triangles:
                drawTrianglesShape(verts)
            case .triangleStrip:
                drawTriangleStripShape(verts)
            case .triangleFan:
                drawTriangleFanShape(verts)
            }
        }
    }

    /// 展開された頂点データ（位置 + オプションのカラー/UV）
    private struct ExpandedVertex {
        var x: Float
        var y: Float
        var color: SIMD4<Float>?
        var u: Float?
        var v: Float?

        var tuple: (Float, Float) { (x, y) }
    }

    /// ShapeVertexType配列を展開してExpandedVertexの配列に変換
    private func expandShapeVerticesEx() -> [ExpandedVertex] {
        var result: [ExpandedVertex] = []
        result.reserveCapacity(shapeVertexList.count * 4)

        var hasCurves = false
        var hasBeziers = false

        for v in shapeVertexList {
            switch v {
            case .curve: hasCurves = true
            case .bezier: hasBeziers = true
            default: break
            }
        }

        if !hasCurves && !hasBeziers {
            for v in shapeVertexList {
                switch v {
                case .normal(let x, let y):
                    result.append(ExpandedVertex(x: x, y: y))
                case .colored(let x, let y, let c):
                    result.append(ExpandedVertex(x: x, y: y, color: c))
                case .textured(let x, let y, let u, let v):
                    result.append(ExpandedVertex(x: x, y: y, u: u, v: v))
                default: break
                }
            }
            return result
        }

        if hasCurves {
            var curvePoints: [(Float, Float)] = []
            for v in shapeVertexList {
                if case .curve(let x, let y) = v {
                    curvePoints.append((x, y))
                }
            }
            if curvePoints.count >= 4 {
                let s = (1 - curveTightnessValue) / 2
                for i in 1..<(curvePoints.count - 2) {
                    let p0 = curvePoints[i - 1]
                    let p1 = curvePoints[i]
                    let p2 = curvePoints[i + 1]
                    let p3 = curvePoints[i + 2]
                    if i == 1 { result.append(ExpandedVertex(x: p1.0, y: p1.1)) }
                    for step in 1...curveDetailCount {
                        let t = Float(step) / Float(curveDetailCount)
                        let t2 = t * t
                        let t3 = t2 * t
                        let x = s * ((-p0.0 + 3 * p1.0 - 3 * p2.0 + p3.0) * t3
                                    + (2 * p0.0 - 5 * p1.0 + 4 * p2.0 - p3.0) * t2
                                    + (-p0.0 + p2.0) * t
                                    + 2 * p1.0) / 1.0
                            + (1 - s) * curvePointLinear(p1.0, p2.0, t)
                        let y = s * ((-p0.1 + 3 * p1.1 - 3 * p2.1 + p3.1) * t3
                                    + (2 * p0.1 - 5 * p1.1 + 4 * p2.1 - p3.1) * t2
                                    + (-p0.1 + p2.1) * t
                                    + 2 * p1.1) / 1.0
                            + (1 - s) * curvePointLinear(p1.1, p2.1, t)
                        result.append(ExpandedVertex(x: x, y: y))
                    }
                }
            }
            return result
        }

        var lastX: Float = 0, lastY: Float = 0
        for v in shapeVertexList {
            switch v {
            case .normal(let x, let y):
                result.append(ExpandedVertex(x: x, y: y))
                lastX = x; lastY = y
            case .colored(let x, let y, let c):
                result.append(ExpandedVertex(x: x, y: y, color: c))
                lastX = x; lastY = y
            case .textured(let x, let y, let u, let v):
                result.append(ExpandedVertex(x: x, y: y, u: u, v: v))
                lastX = x; lastY = y
            case .bezier(let cx1, let cy1, let cx2, let cy2, let x, let y):
                let segments = curveDetailCount
                for step in 1...segments {
                    let t = Float(step) / Float(segments)
                    let px = bezierPoint(lastX, cx1, cx2, x, t)
                    let py = bezierPoint(lastY, cy1, cy2, y, t)
                    result.append(ExpandedVertex(x: px, y: py))
                }
                lastX = x; lastY = y
            case .curve:
                break
            }
        }
        return result
    }

    /// ShapeVertexType配列を展開して(Float, Float)の配列に変換（後方互換）
    private func expandShapeVertices() -> [(Float, Float)] {
        expandShapeVerticesEx().map { $0.tuple }
    }

    private func curvePointLinear(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    // MARK: - Private: Shape Tessellation

    /// 多角形の描画（fill: ear-clippingテッセレーション、stroke: エッジライン）
    private func drawPolygonShape(_ verts: [(Float, Float)], close: CloseMode) {
        // Fill: ear-clipping tessellation（凹多角形対応）
        if hasFill && verts.count >= 3 {
            if contourVertices.isEmpty {
                // 穴なし: 直接テッセレーション
                let indices = EarClipTriangulator.triangulate(verts)
                var i = 0
                while i + 2 < indices.count {
                    addTriangle(
                        verts[indices[i]].0, verts[indices[i]].1,
                        verts[indices[i + 1]].0, verts[indices[i + 1]].1,
                        verts[indices[i + 2]].0, verts[indices[i + 2]].1,
                        fillColor
                    )
                    i += 3
                }
            } else {
                // 穴あり: 外周と穴を結合してからテッセレーション
                let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
                    outer: verts,
                    holes: contourVertices
                )
                var i = 0
                while i + 2 < indices.count {
                    addTriangle(
                        merged[indices[i]].0, merged[indices[i]].1,
                        merged[indices[i + 1]].0, merged[indices[i + 1]].1,
                        merged[indices[i + 2]].0, merged[indices[i + 2]].1,
                        fillColor
                    )
                    i += 3
                }
            }
        }

        // Stroke: strokePolylineでエッジを描画
        if hasStroke && verts.count >= 2 {
            strokePolyline(verts, closed: close == .close)
        }
    }

    /// 点の描画
    private func drawPointsShape(_ verts: [(Float, Float)]) {
        for v in verts {
            point(v.0, v.1)
        }
    }

    /// 線分ペアの描画（2頂点ずつ消費）
    private func drawLinesShape(_ verts: [(Float, Float)]) {
        guard hasStroke else { return }
        var i = 0
        while i + 1 < verts.count {
            strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
            i += 2
        }
    }

    /// 三角形列の描画（3頂点ずつ消費）
    private func drawTrianglesShape(_ verts: [(Float, Float)]) {
        var i = 0
        while i + 2 < verts.count {
            if hasFill {
                addTriangle(
                    verts[i].0, verts[i].1,
                    verts[i + 1].0, verts[i + 1].1,
                    verts[i + 2].0, verts[i + 2].1,
                    fillColor
                )
            }
            if hasStroke {
                strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
                strokeLine(verts[i + 1].0, verts[i + 1].1, verts[i + 2].0, verts[i + 2].1)
                strokeLine(verts[i + 2].0, verts[i + 2].1, verts[i].0, verts[i].1)
            }
            i += 3
        }
    }

    /// トライアングルストリップの描画
    private func drawTriangleStripShape(_ verts: [(Float, Float)]) {
        guard verts.count >= 3 else { return }
        for i in 0..<(verts.count - 2) {
            // ワインディングを交互にする
            let (a, b, c) = i % 2 == 0
                ? (verts[i], verts[i + 1], verts[i + 2])
                : (verts[i + 1], verts[i], verts[i + 2])

            if hasFill {
                addTriangle(a.0, a.1, b.0, b.1, c.0, c.1, fillColor)
            }
            if hasStroke {
                strokeLine(a.0, a.1, b.0, b.1)
                strokeLine(b.0, b.1, c.0, c.1)
                strokeLine(c.0, c.1, a.0, a.1)
            }
        }
    }

    /// トライアングルファンの描画
    private func drawTriangleFanShape(_ verts: [(Float, Float)]) {
        guard verts.count >= 3 else { return }
        for i in 1..<(verts.count - 1) {
            if hasFill {
                addTriangle(
                    verts[0].0, verts[0].1,
                    verts[i].0, verts[i].1,
                    verts[i + 1].0, verts[i + 1].1,
                    fillColor
                )
            }
            if hasStroke {
                strokeLine(verts[0].0, verts[0].1, verts[i].0, verts[i].1)
                strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
            }
        }
        // ファンの最後のエッジ
        if hasStroke && verts.count >= 3 {
            strokeLine(verts[verts.count - 1].0, verts[verts.count - 1].1, verts[0].0, verts[0].1)
        }
    }

    // MARK: - Private: Per-Vertex Color Shape Drawing

    /// 頂点カラー対応の多角形描画
    private func drawPolygonShapeEx(_ verts: [ExpandedVertex], close: CloseMode) {
        if hasFill && verts.count >= 3 {
            let tuples = verts.map { $0.tuple }
            let indices = EarClipTriangulator.triangulate(tuples)
            var i = 0
            while i + 2 < indices.count {
                let v0 = verts[indices[i]]
                let v1 = verts[indices[i + 1]]
                let v2 = verts[indices[i + 2]]
                addVertex(v0.x, v0.y, v0.color ?? fillColor)
                addVertex(v1.x, v1.y, v1.color ?? fillColor)
                addVertex(v2.x, v2.y, v2.color ?? fillColor)
                i += 3
            }
        }
        if hasStroke && verts.count >= 2 {
            strokePolyline(verts.map { $0.tuple }, closed: close == .close)
        }
    }

    /// 頂点カラー対応の三角形列描画
    private func drawTrianglesShapeEx(_ verts: [ExpandedVertex]) {
        var i = 0
        while i + 2 < verts.count {
            if hasFill {
                addVertex(verts[i].x, verts[i].y, verts[i].color ?? fillColor)
                addVertex(verts[i+1].x, verts[i+1].y, verts[i+1].color ?? fillColor)
                addVertex(verts[i+2].x, verts[i+2].y, verts[i+2].color ?? fillColor)
            }
            if hasStroke {
                strokeLine(verts[i].x, verts[i].y, verts[i+1].x, verts[i+1].y)
                strokeLine(verts[i+1].x, verts[i+1].y, verts[i+2].x, verts[i+2].y)
                strokeLine(verts[i+2].x, verts[i+2].y, verts[i].x, verts[i].y)
            }
            i += 3
        }
    }

    /// 頂点カラー対応のトライアングルストリップ描画
    private func drawTriangleStripShapeEx(_ verts: [ExpandedVertex]) {
        guard verts.count >= 3 else { return }
        for i in 0..<(verts.count - 2) {
            let (a, b, c) = i % 2 == 0
                ? (verts[i], verts[i + 1], verts[i + 2])
                : (verts[i + 1], verts[i], verts[i + 2])
            if hasFill {
                addVertex(a.x, a.y, a.color ?? fillColor)
                addVertex(b.x, b.y, b.color ?? fillColor)
                addVertex(c.x, c.y, c.color ?? fillColor)
            }
            if hasStroke {
                strokeLine(a.x, a.y, b.x, b.y)
                strokeLine(b.x, b.y, c.x, c.y)
                strokeLine(c.x, c.y, a.x, a.y)
            }
        }
    }

    /// 頂点カラー対応のトライアングルファン描画
    private func drawTriangleFanShapeEx(_ verts: [ExpandedVertex]) {
        guard verts.count >= 3 else { return }
        for i in 1..<(verts.count - 1) {
            if hasFill {
                addVertex(verts[0].x, verts[0].y, verts[0].color ?? fillColor)
                addVertex(verts[i].x, verts[i].y, verts[i].color ?? fillColor)
                addVertex(verts[i+1].x, verts[i+1].y, verts[i+1].color ?? fillColor)
            }
            if hasStroke {
                strokeLine(verts[0].x, verts[0].y, verts[i].x, verts[i].y)
                strokeLine(verts[i].x, verts[i].y, verts[i+1].x, verts[i+1].y)
            }
        }
        if hasStroke && verts.count >= 3 {
            strokeLine(verts[verts.count - 1].x, verts[verts.count - 1].y, verts[0].x, verts[0].y)
        }
    }

    // MARK: - Private: Vertex Writing

    /// トランスフォームを適用して頂点を追加
    private func addVertex(_ x: Float, _ y: Float, _ color: SIMD4<Float>) {
        hasDrawnAnything = true
        if bufferOffset + vertexCount >= maxVertices {
            flush()
            bufferOffset = 0  // フラッシュ済みデータはGPUコマンドバッファに取り込まれているため再利用可能
        }
        let p = currentTransform * SIMD3<Float>(x, y, 1)
        vertices[bufferOffset + vertexCount] = Vertex2D(
            posX: p.x, posY: p.y,
            r: color.x, g: color.y, b: color.z, a: color.w
        )
        vertexCount += 1
    }

    /// トランスフォームなしで頂点を追加（background用）
    private func addVertexRaw(_ x: Float, _ y: Float, _ color: SIMD4<Float>) {
        if bufferOffset + vertexCount >= maxVertices {
            flush()
            bufferOffset = 0
        }
        vertices[bufferOffset + vertexCount] = Vertex2D(
            posX: x, posY: y,
            r: color.x, g: color.y, b: color.z, a: color.w
        )
        vertexCount += 1
    }

    /// トランスフォーム付き三角形を追加
    private func addTriangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ color: SIMD4<Float>
    ) {
        addVertex(x1, y1, color)
        addVertex(x2, y2, color)
        addVertex(x3, y3, color)
    }

    /// ストロークライン（quad展開 + キャップ）
    private func strokeLine(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float,
                            capStart: Bool = true, capEnd: Bool = true) {
        let dx = x2 - x1
        let dy = y2 - y1
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }

        let hw = currentStrokeWeight * 0.5
        let nx = -dy / len * hw
        let ny = dx / len * hw
        // 方向ベクトル（正規化済み * hw）
        let tx = dx / len * hw
        let ty = dy / len * hw

        // square cap: 始点/終点をhw分延長
        var sx1 = x1, sy1 = y1, sx2 = x2, sy2 = y2
        if currentStrokeCap == .square {
            if capStart { sx1 -= tx; sy1 -= ty }
            if capEnd   { sx2 += tx; sy2 += ty }
        }

        // メインquad
        addVertex(sx1 + nx, sy1 + ny, strokeColor)
        addVertex(sx1 - nx, sy1 - ny, strokeColor)
        addVertex(sx2 + nx, sy2 + ny, strokeColor)
        addVertex(sx1 - nx, sy1 - ny, strokeColor)
        addVertex(sx2 - nx, sy2 - ny, strokeColor)
        addVertex(sx2 + nx, sy2 + ny, strokeColor)

        // round cap: 半円fan
        if currentStrokeCap == .round {
            let capSegments = 8
            if capStart {
                let baseAngle = atan2(-dy, -dx) // 始点から逆方向
                for i in 0..<capSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(capSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(capSegments)
                    addVertex(x1, y1, strokeColor)
                    addVertex(x1 + hw * cos(a0), y1 + hw * sin(a0), strokeColor)
                    addVertex(x1 + hw * cos(a1), y1 + hw * sin(a1), strokeColor)
                }
            }
            if capEnd {
                let baseAngle = atan2(dy, dx) // 終点方向
                for i in 0..<capSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(capSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(capSegments)
                    addVertex(x2, y2, strokeColor)
                    addVertex(x2 + hw * cos(a0), y2 + hw * sin(a0), strokeColor)
                    addVertex(x2 + hw * cos(a1), y2 + hw * sin(a1), strokeColor)
                }
            }
        }
    }

    /// ポリラインストローク描画（join対応）
    private func strokePolyline(_ points: [(Float, Float)], closed: Bool) {
        let count = points.count
        guard count >= 2 else { return }

        let hw = currentStrokeWeight * 0.5
        let joinSegments = 8

        // 各セグメントの方向・法線を事前計算
        struct SegInfo {
            var dx: Float; var dy: Float; var len: Float
            var nx: Float; var ny: Float
        }

        let segCount = closed ? count : count - 1
        var segs: [SegInfo] = []
        segs.reserveCapacity(segCount)

        for i in 0..<segCount {
            let j = (i + 1) % count
            let dx = points[j].0 - points[i].0
            let dy = points[j].1 - points[i].1
            let len = sqrt(dx * dx + dy * dy)
            if len > 0 {
                segs.append(SegInfo(dx: dx, dy: dy, len: len,
                                    nx: -dy / len * hw, ny: dx / len * hw))
            } else {
                segs.append(SegInfo(dx: 0, dy: 0, len: 0, nx: 0, ny: 0))
            }
        }

        // 各セグメントをquad描画（キャップなし）
        for i in 0..<segCount {
            let s = segs[i]
            guard s.len > 0 else { continue }
            let p0 = points[i]
            let p1 = points[(i + 1) % count]
            addVertex(p0.0 + s.nx, p0.1 + s.ny, strokeColor)
            addVertex(p0.0 - s.nx, p0.1 - s.ny, strokeColor)
            addVertex(p1.0 + s.nx, p1.1 + s.ny, strokeColor)
            addVertex(p0.0 - s.nx, p0.1 - s.ny, strokeColor)
            addVertex(p1.0 - s.nx, p1.1 - s.ny, strokeColor)
            addVertex(p1.0 + s.nx, p1.1 + s.ny, strokeColor)
        }

        // joinジオメトリ
        let joinCount = closed ? count : count - 2
        let joinStart = closed ? 0 : 1
        for k in 0..<joinCount {
            let idx = (joinStart + k) % count
            let prevSeg = closed ? (idx - 1 + segCount) % segCount : idx - 1
            let nextSeg = closed ? idx : idx

            let s0 = segs[prevSeg]
            let s1 = segs[nextSeg]
            guard s0.len > 0 && s1.len > 0 else { continue }

            let px = points[idx].0
            let py = points[idx].1

            // 外積で曲がる方向を判定（正=左折、負=右折）
            let cross = s0.dx * s1.dy - s0.dy * s1.dx

            switch currentStrokeJoin {
            case .bevel:
                // 外側に三角形1枚
                if cross > 0 {
                    // 左折: 外側は法線の(-)側
                    addVertex(px, py, strokeColor)
                    addVertex(px - s0.nx, py - s0.ny, strokeColor)
                    addVertex(px - s1.nx, py - s1.ny, strokeColor)
                } else {
                    // 右折: 外側は法線の(+)側
                    addVertex(px, py, strokeColor)
                    addVertex(px + s0.nx, py + s0.ny, strokeColor)
                    addVertex(px + s1.nx, py + s1.ny, strokeColor)
                }

            case .miter:
                // miter接合: 法線の交差点を計算
                let dot = s0.nx * s1.nx + s0.ny * s1.ny
                let miterLen = hw / max(sqrt((1.0 + dot / (hw * hw)) * 0.5), 0.001)
                // miter limit (4x) を超えたらbevel fallback
                if miterLen > hw * 4.0 {
                    // bevel fallback
                    if cross > 0 {
                        addVertex(px, py, strokeColor)
                        addVertex(px - s0.nx, py - s0.ny, strokeColor)
                        addVertex(px - s1.nx, py - s1.ny, strokeColor)
                    } else {
                        addVertex(px, py, strokeColor)
                        addVertex(px + s0.nx, py + s0.ny, strokeColor)
                        addVertex(px + s1.nx, py + s1.ny, strokeColor)
                    }
                } else {
                    // miter: 外側の2辺の延長線の交点
                    if cross > 0 {
                        // 外側: (-)方向
                        let mx = -(s0.nx + s1.nx)
                        let my = -(s0.ny + s1.ny)
                        let mlen = sqrt(mx * mx + my * my)
                        if mlen > 0 {
                            let scale = miterLen / mlen
                            addVertex(px, py, strokeColor)
                            addVertex(px - s0.nx, py - s0.ny, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px, py, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px - s1.nx, py - s1.ny, strokeColor)
                        }
                    } else {
                        let mx = s0.nx + s1.nx
                        let my = s0.ny + s1.ny
                        let mlen = sqrt(mx * mx + my * my)
                        if mlen > 0 {
                            let scale = miterLen / mlen
                            addVertex(px, py, strokeColor)
                            addVertex(px + s0.nx, py + s0.ny, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px, py, strokeColor)
                            addVertex(px + mx * scale, py + my * scale, strokeColor)
                            addVertex(px + s1.nx, py + s1.ny, strokeColor)
                        }
                    }
                }

            case .round:
                // 円弧fan
                let angle0: Float
                let angle1: Float
                if cross > 0 {
                    angle0 = atan2(-s0.ny, -s0.nx)
                    angle1 = atan2(-s1.ny, -s1.nx)
                } else {
                    angle0 = atan2(s0.ny, s0.nx)
                    angle1 = atan2(s1.ny, s1.nx)
                }
                var sweep = angle1 - angle0
                if cross > 0 {
                    if sweep > 0 { sweep -= Float.pi * 2 }
                } else {
                    if sweep < 0 { sweep += Float.pi * 2 }
                }

                for i in 0..<joinSegments {
                    let a0 = angle0 + sweep * Float(i) / Float(joinSegments)
                    let a1 = angle0 + sweep * Float(i + 1) / Float(joinSegments)
                    addVertex(px, py, strokeColor)
                    addVertex(px + hw * cos(a0), py + hw * sin(a0), strokeColor)
                    addVertex(px + hw * cos(a1), py + hw * sin(a1), strokeColor)
                }
            }
        }

        // 開いたパスの端にキャップ
        if !closed {
            let s0 = segs[0]
            let sLast = segs[segCount - 1]

            if currentStrokeCap == .round && s0.len > 0 {
                let baseAngle = atan2(-s0.dy, -s0.dx)
                let p = points[0]
                for i in 0..<joinSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(joinSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(joinSegments)
                    addVertex(p.0, p.1, strokeColor)
                    addVertex(p.0 + hw * cos(a0), p.1 + hw * sin(a0), strokeColor)
                    addVertex(p.0 + hw * cos(a1), p.1 + hw * sin(a1), strokeColor)
                }
            } else if currentStrokeCap == .square && s0.len > 0 {
                let tx = s0.dx / s0.len * hw
                let ty = s0.dy / s0.len * hw
                let p = points[0]
                addVertex(p.0 + s0.nx - tx, p.1 + s0.ny - ty, strokeColor)
                addVertex(p.0 - s0.nx - tx, p.1 - s0.ny - ty, strokeColor)
                addVertex(p.0 + s0.nx, p.1 + s0.ny, strokeColor)
                addVertex(p.0 - s0.nx - tx, p.1 - s0.ny - ty, strokeColor)
                addVertex(p.0 - s0.nx, p.1 - s0.ny, strokeColor)
                addVertex(p.0 + s0.nx, p.1 + s0.ny, strokeColor)
            }

            if currentStrokeCap == .round && sLast.len > 0 {
                let baseAngle = atan2(sLast.dy, sLast.dx)
                let p = points[count - 1]
                for i in 0..<joinSegments {
                    let a0 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i) / Float(joinSegments)
                    let a1 = baseAngle - Float.pi * 0.5 + Float.pi * Float(i + 1) / Float(joinSegments)
                    addVertex(p.0, p.1, strokeColor)
                    addVertex(p.0 + hw * cos(a0), p.1 + hw * sin(a0), strokeColor)
                    addVertex(p.0 + hw * cos(a1), p.1 + hw * sin(a1), strokeColor)
                }
            } else if currentStrokeCap == .square && sLast.len > 0 {
                let tx = sLast.dx / sLast.len * hw
                let ty = sLast.dy / sLast.len * hw
                let p = points[count - 1]
                addVertex(p.0 + sLast.nx, p.1 + sLast.ny, strokeColor)
                addVertex(p.0 - sLast.nx, p.1 - sLast.ny, strokeColor)
                addVertex(p.0 + sLast.nx + tx, p.1 + sLast.ny + ty, strokeColor)
                addVertex(p.0 - sLast.nx, p.1 - sLast.ny, strokeColor)
                addVertex(p.0 - sLast.nx + tx, p.1 - sLast.ny + ty, strokeColor)
                addVertex(p.0 + sLast.nx + tx, p.1 + sLast.ny + ty, strokeColor)
            }
        }
    }

    // MARK: - Private: Textured Quad

    /// テクスチャ付きクワッドを描画（image/text共通）
    /// - Parameters:
    ///   - srcX/srcY/srcW/srcH: ソース矩形（ピクセル単位、nilで全体）
    private func drawTexturedQuad(
        texture: MTLTexture, x: Float, y: Float, w: Float, h: Float,
        srcX: Float = 0, srcY: Float = 0, srcW: Float? = nil, srcH: Float? = nil
    ) {
        guard let encoder = encoder else { return }

        flush()

        let tw = Float(texture.width)
        let th = Float(texture.height)
        let u0 = srcX / tw
        let v0 = srcY / th
        let u1 = (srcX + (srcW ?? tw)) / tw
        let v1 = (srcY + (srcH ?? th)) / th

        let tint = hasTint ? tintColor : SIMD4<Float>(1, 1, 1, 1)
        let p0 = currentTransform * SIMD3<Float>(x, y, 1)
        let p1 = currentTransform * SIMD3<Float>(x + w, y, 1)
        let p2 = currentTransform * SIMD3<Float>(x + w, y + h, 1)
        let p3 = currentTransform * SIMD3<Float>(x, y + h, 1)

        var verts: [TexturedVertex2D] = [
            TexturedVertex2D(posX: p0.x, posY: p0.y, u: u0, v: v0, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p1.x, posY: p1.y, u: u1, v: v0, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p2.x, posY: p2.y, u: u1, v: v1, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p0.x, posY: p0.y, u: u0, v: v0, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p2.x, posY: p2.y, u: u1, v: v1, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p3.x, posY: p3.y, u: u0, v: v1, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
        ]

        guard let texPipeline = texturedPipelineStates[currentBlendMode] else { return }
        encoder.setRenderPipelineState(texPipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBytes(&verts, length: MemoryLayout<TexturedVertex2D>.stride * 6, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    /// アトラスからバッチテキスト描画（全グリフを1回のドローコールで描画）
    private func drawTextFromAtlas(
        texture: MTLTexture,
        glyphs: [PositionedGlyph],
        x: Float, y: Float
    ) {
        guard let encoder = encoder, !glyphs.isEmpty else { return }

        flush()

        let tint = hasTint ? tintColor : SIMD4<Float>(1, 1, 1, 1)
        let r = tint.x, g = tint.y, b = tint.z, a = tint.w

        var verts: [TexturedVertex2D] = []
        verts.reserveCapacity(glyphs.count * 6)

        for glyph in glyphs {
            let gx = x + glyph.x
            let gy = y + glyph.y
            let gw = glyph.width
            let gh = glyph.height

            let p0 = currentTransform * SIMD3<Float>(gx, gy, 1)
            let p1 = currentTransform * SIMD3<Float>(gx + gw, gy, 1)
            let p2 = currentTransform * SIMD3<Float>(gx + gw, gy + gh, 1)
            let p3 = currentTransform * SIMD3<Float>(gx, gy + gh, 1)

            verts.append(TexturedVertex2D(posX: p0.x, posY: p0.y, u: glyph.u0, v: glyph.v0, r: r, g: g, b: b, a: a))
            verts.append(TexturedVertex2D(posX: p1.x, posY: p1.y, u: glyph.u1, v: glyph.v0, r: r, g: g, b: b, a: a))
            verts.append(TexturedVertex2D(posX: p2.x, posY: p2.y, u: glyph.u1, v: glyph.v1, r: r, g: g, b: b, a: a))
            verts.append(TexturedVertex2D(posX: p0.x, posY: p0.y, u: glyph.u0, v: glyph.v0, r: r, g: g, b: b, a: a))
            verts.append(TexturedVertex2D(posX: p2.x, posY: p2.y, u: glyph.u1, v: glyph.v1, r: r, g: g, b: b, a: a))
            verts.append(TexturedVertex2D(posX: p3.x, posY: p3.y, u: glyph.u0, v: glyph.v1, r: r, g: g, b: b, a: a))
        }

        guard let texPipeline = texturedPipelineStates[currentBlendMode] else { return }
        encoder.setRenderPipelineState(texPipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBytes(&verts, length: MemoryLayout<TexturedVertex2D>.stride * verts.count, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }
}

// MARK: - Errors

public enum Canvas2DError: Error {
    case bufferCreationFailed
}
