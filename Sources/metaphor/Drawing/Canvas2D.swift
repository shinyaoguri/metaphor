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
    private let vertexBuffer: MTLBuffer
    private let vertices: UnsafeMutablePointer<Vertex2D>

    // MARK: - Dimensions

    /// キャンバスの幅（ピクセル）
    public let width: Float

    /// キャンバスの高さ（ピクセル）
    public let height: Float

    // MARK: - Constants

    private let maxVertices: Int = 65536
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

    // MARK: - Text State

    private var currentTextSize: Float = 32
    private var currentFontFamily: String = "Helvetica"
    private var currentTextAlignH: TextAlignH = .left
    private var currentTextAlignV: TextAlignV = .baseline
    private let textRenderer: TextRenderer
    private var frameCounter: Int = 0

    // MARK: - Curve State

    private var curveDetailCount: Int = 20
    private var curveTightnessValue: Float = 0.0

    // MARK: - Shape Building State

    private enum ShapeVertexType {
        case normal(Float, Float)
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
        var curveDetail: Int
        var curveTightness: Float
    }

    // MARK: - Transform & Style Stack

    private var stateStack: [StyleState] = []
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
            height: Float(renderer.textureManager.height)
        )
    }

    /// コンポーネントから生成
    public init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Float,
        height: Float
    ) throws {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.width = width
        self.height = height

        // 頂点バッファ（事前確保）
        let bufferSize = maxVertices * MemoryLayout<Vertex2D>.stride
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw Canvas2DError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
        self.vertices = buffer.contents().bindMemory(to: Vertex2D.self, capacity: maxVertices)

        // カラーパイプライン（全BlendMode分）
        let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DVertex,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )

        var colorPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            colorPipelines[mode] = try PipelineFactory(device: device)
                .vertex(vertexFn)
                .fragment(fragmentFn)
                .vertexLayout(.position2DColor)
                .blending(mode)
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

        var texPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            texPipelines[mode] = try PipelineFactory(device: device)
                .vertex(texVertexFn)
                .fragment(texFragmentFn)
                .vertexLayout(.position2DTexCoordColor)
                .blending(mode)
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

    /// 描画開始。毎フレームencoderを渡す。
    public func begin(encoder: MTLRenderCommandEncoder) {
        self.encoder = encoder
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
        self.currentTextSize = 32
        self.currentFontFamily = "Helvetica"
        self.currentTextAlignH = .left
        self.currentTextAlignV = .baseline
        self.frameCounter += 1
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

    // MARK: - Background

    /// 背景を塗りつぶす（トランスフォーム無視）
    public func background(_ color: Color) {
        let c = color.simd
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
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue
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
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        // ブレンドモードが変わった場合はフラッシュ
        if prevBlendMode != currentBlendMode {
            flush()
        }
    }

    /// スタイル状態のみを保存（トランスフォームは含まない）
    public func pushStyle() {
        push()
    }

    /// スタイル状態のみを復元
    public func popStyle() {
        pop()
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
            strokeLine(rx, ry, rx + rw, ry)
            strokeLine(rx + rw, ry, rx + rw, ry + rh)
            strokeLine(rx + rw, ry + rh, rx, ry + rh)
            strokeLine(rx, ry + rh, rx, ry)
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

    /// 多角形（頂点配列）
    public func polygon(_ points: [(Float, Float)]) {
        guard points.count >= 3 else { return }

        if hasFill {
            for i in 1..<(points.count - 1) {
                addTriangle(
                    points[0].0, points[0].1,
                    points[i].0, points[i].1,
                    points[i + 1].0, points[i + 1].1,
                    fillColor
                )
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

    /// テキストの描画幅を取得
    public func textWidth(_ string: String) -> Float {
        textRenderer.textWidth(string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// テキストを描画
    public func text(_ string: String, _ x: Float, _ y: Float) {
        guard !string.isEmpty else { return }
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

    // MARK: - Custom Shapes (beginShape / endShape)

    /// 頂点ベースの形状記録を開始
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape = true
        shapeMode = mode
        shapeVertexList.removeAll(keepingCapacity: true)
    }

    /// 形状に頂点を追加（beginShape〜endShape間で使用）
    public func vertex(_ x: Float, _ y: Float) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.normal(x, y))
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

        // カーブ/ベジェ頂点を展開して(Float, Float)に変換
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

    /// ShapeVertexType配列を展開して(Float, Float)の配列に変換
    private func expandShapeVertices() -> [(Float, Float)] {
        var result: [(Float, Float)] = []
        result.reserveCapacity(shapeVertexList.count * 4)

        // カーブ頂点だけを集めてバッチ処理
        var curvePoints: [(Float, Float)] = []
        var hasCurves = false
        var hasBeziers = false

        for v in shapeVertexList {
            switch v {
            case .curve: hasCurves = true
            case .bezier: hasBeziers = true
            case .normal: break
            }
        }

        if !hasCurves && !hasBeziers {
            // 最適化: 全部normalなら直接変換
            for v in shapeVertexList {
                if case .normal(let x, let y) = v {
                    result.append((x, y))
                }
            }
            return result
        }

        // カーブ頂点がある場合: curve頂点をまとめて展開
        if hasCurves {
            for v in shapeVertexList {
                if case .curve(let x, let y) = v {
                    curvePoints.append((x, y))
                }
            }
            // Catmull-Romは4点必要。最初と最後は制御点。
            if curvePoints.count >= 4 {
                let s = (1 - curveTightnessValue) / 2
                for i in 1..<(curvePoints.count - 2) {
                    let p0 = curvePoints[i - 1]
                    let p1 = curvePoints[i]
                    let p2 = curvePoints[i + 1]
                    let p3 = curvePoints[i + 2]
                    if i == 1 { result.append(p1) }
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
                        result.append((x, y))
                    }
                }
            }
            return result
        }

        // ベジェ頂点がある場合: normal + bezier を順に展開
        var lastX: Float = 0, lastY: Float = 0
        for v in shapeVertexList {
            switch v {
            case .normal(let x, let y):
                result.append((x, y))
                lastX = x; lastY = y
            case .bezier(let cx1, let cy1, let cx2, let cy2, let x, let y):
                let segments = curveDetailCount
                for step in 1...segments {
                    let t = Float(step) / Float(segments)
                    let px = bezierPoint(lastX, cx1, cx2, x, t)
                    let py = bezierPoint(lastY, cy1, cy2, y, t)
                    result.append((px, py))
                }
                lastX = x; lastY = y
            case .curve:
                break // カーブとベジェの混在はカーブ側で処理済み
            }
        }
        return result
    }

    private func curvePointLinear(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    // MARK: - Private: Shape Tessellation

    /// 多角形の描画（fill: fanテッセレーション、stroke: エッジライン）
    private func drawPolygonShape(_ verts: [(Float, Float)], close: CloseMode) {
        // Fill: fan tessellation（凸多角形で正確）
        if hasFill && verts.count >= 3 {
            for i in 1..<(verts.count - 1) {
                addTriangle(
                    verts[0].0, verts[0].1,
                    verts[i].0, verts[i].1,
                    verts[i + 1].0, verts[i + 1].1,
                    fillColor
                )
            }
        }

        // Stroke: エッジを描画
        if hasStroke && verts.count >= 2 {
            for i in 0..<(verts.count - 1) {
                strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
            }
            if close == .close {
                let last = verts[verts.count - 1]
                let first = verts[0]
                strokeLine(last.0, last.1, first.0, first.1)
            }
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

    // MARK: - Private: Vertex Writing

    /// トランスフォームを適用して頂点を追加
    private func addVertex(_ x: Float, _ y: Float, _ color: SIMD4<Float>) {
        guard bufferOffset + vertexCount < maxVertices else { return }
        let p = currentTransform * SIMD3<Float>(x, y, 1)
        vertices[bufferOffset + vertexCount] = Vertex2D(
            posX: p.x, posY: p.y,
            r: color.x, g: color.y, b: color.z, a: color.w
        )
        vertexCount += 1
    }

    /// トランスフォームなしで頂点を追加（background用）
    private func addVertexRaw(_ x: Float, _ y: Float, _ color: SIMD4<Float>) {
        guard bufferOffset + vertexCount < maxVertices else { return }
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

    /// ストロークライン（quad展開）
    private func strokeLine(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        let dx = x2 - x1
        let dy = y2 - y1
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return }

        let hw = currentStrokeWeight * 0.5
        let nx = -dy / len * hw
        let ny = dx / len * hw

        addVertex(x1 + nx, y1 + ny, strokeColor)
        addVertex(x1 - nx, y1 - ny, strokeColor)
        addVertex(x2 + nx, y2 + ny, strokeColor)
        addVertex(x1 - nx, y1 - ny, strokeColor)
        addVertex(x2 - nx, y2 - ny, strokeColor)
        addVertex(x2 + nx, y2 + ny, strokeColor)
    }

    // MARK: - Private: Textured Quad

    /// テクスチャ付きクワッドを描画（image/text共通）
    private func drawTexturedQuad(texture: MTLTexture, x: Float, y: Float, w: Float, h: Float) {
        guard let encoder = encoder else { return }

        // 現在の頂点カラージオメトリをフラッシュ
        flush()

        let tint = hasTint ? tintColor : SIMD4<Float>(1, 1, 1, 1)
        let p0 = currentTransform * SIMD3<Float>(x, y, 1)
        let p1 = currentTransform * SIMD3<Float>(x + w, y, 1)
        let p2 = currentTransform * SIMD3<Float>(x + w, y + h, 1)
        let p3 = currentTransform * SIMD3<Float>(x, y + h, 1)

        var verts: [TexturedVertex2D] = [
            TexturedVertex2D(posX: p0.x, posY: p0.y, u: 0, v: 0, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p1.x, posY: p1.y, u: 1, v: 0, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p2.x, posY: p2.y, u: 1, v: 1, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p0.x, posY: p0.y, u: 0, v: 0, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p2.x, posY: p2.y, u: 1, v: 1, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
            TexturedVertex2D(posX: p3.x, posY: p3.y, u: 0, v: 1, r: tint.x, g: tint.y, b: tint.z, a: tint.w),
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
}

// MARK: - Errors

public enum Canvas2DError: Error {
    case bufferCreationFailed
}
