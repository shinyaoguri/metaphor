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

    /// 2D 描画パイプラインの一元的な保持先（#646 / Epic #291 E1）。
    /// 記録側は ``Canvas2DPipelineKey`` を確定させ、再生側はここを引くだけにする。
    let pipelineStore: Canvas2DPipelineStore

    let depthStencilState: MTLDepthStencilState?

    // MARK: - 2D インスタンシングリソース

    let instanceBatcher2D: InstanceBatcher2D
    let unitCircleBuffer: MTLBuffer
    let unitCircleVertexCount: Int
    let unitRectBuffer: MTLBuffer
    let unitRectVertexCount: Int
    let massiveCircleBuffer: GrowableGPUBuffer<CircleInstance>

    // CPU/GPU 同期競合を回避するトリプルバッファ
    private static let bufferCount = 3
    let colorBuffer: GrowableGPUBuffer<Vertex2D>
    let texturedBuffer: GrowableGPUBuffer<TexturedVertex2D>
    var currentBufferIndex: Int = 0

    var texturedVertexCount: Int = 0
    var texturedBufferOffset: Int = 0
    var massiveCircleBufferOffset: Int = 0
    var currentBoundTexture: MTLTexture?

    /// 蓄積中のテクスチャバッチが「straight なテクスチャ」かどうか（`updatePixels()`。#848）。
    ///
    /// 既定は `false` = premultiplied（グリフアトラス・読み込んだ画像・オフスクリーン。
    /// ADR-0012）。`drawTexturedQuad(straightAlpha:)` が切り替え時にバッチを閉じるので、
    /// 蓄積中のバッチは常に単一の系統に属します。
    var texturedIsStraightAlpha: Bool = false

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
    var texturedVertexBuffer: MTLBuffer {
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

    /// 半径から楕円・弧の分割数を算出します（全円換算）。
    ///
    /// n 角形と真円の最大サジッタ誤差が約 0.25px 以下になるよう
    /// `n = π / acos(1 − ε/r)` で選び、32〜128 にクランプします。
    /// `scale()` による拡大は考慮しません（Processing の固定 detail と同じ割り切り）。
    func ellipseSegments(forRadius r: Float) -> Int {
        guard r.isFinite, r > 4 else { return 32 }
        let n = Float.pi / acos(max(-1.0, 1.0 - 0.25 / r))
        return min(128, max(32, Int(n.rounded(.up))))
    }

    // MARK: - フレームごとの状態

    var encoder: MTLRenderCommandEncoder?

    /// 現在のレンダーコマンドエンコーダーにアクセスします。フレーム中のみ有効です。
    public var currentEncoder: MTLRenderCommandEncoder? { encoder }

    /// 遅延（前景）記録モード。シャドウ同一フレーム化（#70）で、2D 描画を
    /// 3D 再生の後にエンコードするため、各 flush を即時描画する代わりに
    /// `deferred2DCommands` に明示コマンドとして積む。影オフ時は常に `false`（無変更）。
    var isDeferring = false

    /// 遅延モードで積まれた前景2D描画コマンド（#71・宿題④でクロージャから昇格）。
    /// `replayForeground(encoder:)` で順に再生する。各 flush 拡張から積むため internal。
    var deferred2DCommands: [Deferred2DSlot] = []

    /// draw() 内の呼び出し順を表す単調シーケンス番号の払い出し元（#71）。
    /// `SketchContext` がフレーム頭でリセットするカウンタを注入する。未注入時は 0。
    /// PR-1 では基盤のみ（2D flush はまだ seq を消費しない）。
    var seqProvider: (() -> UInt32)?

    /// このフレームで 3D 側に記録済みのドローコールがあるかを返すフック
    /// （SketchContext が配線）。遅延モードのフレーム途中 background() 判定に使う。
    var hasRecorded3D: (() -> Bool)?

    /// カスタム 2D シェーダへ渡す組み込み uniform のうち、Canvas2D が持たない値
    /// （時間・マウス・フレーム数）を供給するフック（SketchContext が配線・#647）。
    /// 未注入なら時間 0 / マウス原点で描く（`Graphics` を単体で使う場合など）。
    var shaderInputs: (() -> Canvas2DShaderInputs)?
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

    /// 適用中のカスタムフラグメントシェーダ（#647 / Epic #291 E2）。nil なら組み込みシェーダ。
    var currentShader: Shader2D?

    /// `blendMode(.difference)` / `.exclusion` を通常ブレンドへ落とした警告を出したかどうか。
    private var didWarnBlendFallback = false

    /// `arc()` に `stop <= start` の角度が渡され、何も描かなかった警告を出したかどうか（#743）。
    /// 診断の発火条件はテストから観測する（`metaphorWarning` は print のため）。
    var didWarnArcReversedAngles = false

    /// `arc()` の角度が逆転している（= 何も描かれない）ことを初回だけ警告します。
    func warnArcReversedAnglesOnce() {
        guard !didWarnArcReversedAngles else { return }
        didWarnArcReversedAngles = true
        metaphorWarning(
            "arc(): stopAngle は startAngle より大きい必要があります（Processing 互換）。"
                + "この呼び出しは何も描きません。角度を入れ替えるか、stopAngle に 2π を足してください")
    }

    // MARK: - テキスト状態

    var currentTextSize: Float = 32
    var currentFontFamily: String = "Helvetica"
    var currentTextAlignH: TextAlignH = .left
    var currentTextAlignV: TextAlignV = .baseline
    /// 明示された行の高さ（ピクセル単位）。nil ならフォントから導出します
    /// （``Canvas2D/effectiveTextLeading``）。`textSize()` / `textFont()` で nil に戻ります。
    var currentTextLeading: Float?
    let textRenderer: TextRenderer
    var frameCounter: Int = 0

    /// テキスト描画キャッシュ（テクスチャとグリフアトラス）をすべて破棄します。
    public func clearTextCache() {
        textRenderer.clearCache()
    }

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

    /// レンダーパスの clearColor として、現在のエンコーダー作成時点で有効だった色。
    var appliedClearColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)

    /// このフレームで background() により次フレーム用に予約された clearColor。
    var pendingClearColor: SIMD4<Float>?

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
        var textLeading: Float?
        var curveDetail: Int
        var curveTightness: Float
        var strokeCap: StrokeCap
        var strokeJoin: StrokeJoin
    }

    // MARK: - クリッピング状態

    var clipRect: MTLScissorRect?
    var clipStack: [MTLScissorRect?] = []

    // MARK: - 変換・スタイルスタック

    var stateStack: [StyleState] = []
    var styleOnlyStack: [StyleState] = []
    var matrixStack: [float3x3] = []
    var currentTransform: float3x3 = float3x3(1)

    // MARK: - SVG 記録

    /// アクティブな SVG レコーダー。設定中は図形呼び出しが SVG にも記録される
    /// （``SketchContext/beginSVGRecord(_:)`` / ``SketchContext/endSVGRecord()`` が管理）。
    var svgRecorder: SVGRecorder?

    /// SVG 記録用の現在スタイル・変換のスナップショットを返します。
    func svgStyle() -> SVGRecorder.Style {
        SVGRecorder.Style(
            fill: hasFill ? fillColor : nil,
            stroke: hasStroke ? strokeColor : nil,
            strokeWeight: currentStrokeWeight,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin,
            transform: currentTransform
        )
    }

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
    /// - Throws: ``MetaphorError``。頂点・インスタンスバッファを確保できない場合は
    ///   ``MetaphorError/bufferCreationFailed(size:)``、描画パイプラインを作成できない
    ///   場合（組み込み 2D シェーダー関数が見つからない場合を含む）は
    ///   ``MetaphorError/pipelineCreationFailed(name:underlying:)``。
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
    /// - Throws: ``MetaphorError``。頂点・インスタンスバッファを確保できない場合は
    ///   ``MetaphorError/bufferCreationFailed(size:)``、描画パイプラインを作成できない
    ///   場合（組み込み 2D シェーダー関数が見つからない場合を含む）は
    ///   ``MetaphorError/pipelineCreationFailed(name:underlying:)``。
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
        self.massiveCircleBuffer = try GrowableGPUBuffer<CircleInstance>(
            device: device, initialCapacity: 4096, maxCapacity: 1_000_000,
            label: "metaphor.canvas2D.massiveCircles"
        )

        // 描画パイプライン（系統 × BlendMode の全組み合わせ）は
        // Canvas2DPipelineStore が生成・保持する（#646）。
        self.pipelineStore = try Canvas2DPipelineStore(
            device: device, shaderLibrary: shaderLibrary, sampleCount: sampleCount
        )

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
            throw MetaphorError.bufferCreationFailed(size: 64 * 3 * MemoryLayout<SIMD2<Float>>.stride)
        }
        self.unitCircleBuffer = circleBuf
        self.unitCircleVertexCount = circleCount
        guard let (rectBuf, rectCount) = UnitMesh2D.createRect(device: device) else {
            throw MetaphorError.bufferCreationFailed(size: 6 * MemoryLayout<SIMD2<Float>>.stride)
        }
        self.unitRectBuffer = rectBuf
        self.unitRectVertexCount = rectCount
        self.instanceBatcher2D = try InstanceBatcher2D(device: device)
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
    public func begin(encoder: MTLRenderCommandEncoder?, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentBufferIndex = bufferIndex % Self.bufferCount
        // フレームごとのレンダリング状態をリセット
        self.vertexCount = 0
        self.bufferOffset = 0
        self.texturedVertexCount = 0
        self.texturedBufferOffset = 0
        self.massiveCircleBufferOffset = 0
        self.currentBoundTexture = nil
        self.texturedIsStraightAlpha = false
        self.currentTransform = float3x3(1)
        self.stateStack.removeAll(keepingCapacity: true)
        // 不均衡な pushMatrix()/pushStyle() が draw() 内に残っていても、
        // フレームをまたいでスタックが無限成長したり変換がリークしたり
        // しないよう、stateStack と同様に毎フレーム破棄する。
        self.matrixStack.removeAll(keepingCapacity: true)
        self.styleOnlyStack.removeAll(keepingCapacity: true)
        // スタイル状態（fill、stroke、colorMode など）はフレーム間で保持される。
        // Processing の動作に合わせ、setup() のスタイルが draw() に引き継がれます。
        self.frameCounter += 1
        self.hasDrawnAnything = false
        self.backgroundCalledThisFrame = false
        self.pendingClearColor = nil
        self.deferred2DCommands.removeAll(keepingCapacity: true)
        self.instanceBatcher2D.beginFrame(bufferIndex: currentBufferIndex)
    }

    /// メインパス分割後（`loadPixels()` の同一フレーム読み戻し、#326）に、
    /// 描画先を新しいレンダーコマンドエンコーダへ差し替えます。
    ///
    /// 呼び出し側は分割前に ``flush()`` 済みであること（保留頂点は分割前のパスへ出す）。
    /// フレームごとの状態（変換・スタイル・バッファオフセット）は**維持する** —
    /// `draw()` の途中なので、Processing から見れば同じ 1 フレームの続きだから。
    ///
    /// - Parameter newEncoder: 継続パスのレンダーコマンドエンコーダー。
    func rebindEncoder(_ newEncoder: MTLRenderCommandEncoder) {
        self.encoder = newEncoder
        // 継続パスは loadAction = .load。以降の background() を「Metal のクリア任せ」に
        // 最適化するとクリアが起きずに無視されるため、必ずクワッドを描かせる。
        self.frameWillClear = false
        // シザーはエンコーダごとの状態。新しいエンコーダでは既定（フルビューポート）に
        // 戻るので、クリップ中なら復元する。
        if let rect = clipRect {
            newEncoder.setScissorRect(rect)
        }
    }

    /// 遅延モードで積まれた前景2D描画を、指定エンコーダへ順に再生します（#70 / #71）。
    ///
    /// シャドウ同一フレーム化の経路で、`MetaphorRenderer.renderFrame()` が 3D 再生
    /// （`Canvas3D.replayMainPass`）の後に呼ぶ。記録時の頂点バッファ・状態はフレーム内で
    /// 保持されているため、記録済みコマンドをそのまま再投入すれば正しい描画になる。
    /// 当面は記録順（= 2D 内の seq 昇順）で再生する（3D との呼び出し順マージは PR-3）。
    func replayForeground(encoder: MTLRenderCommandEncoder) {
        replayForegroundRange(0..<deferred2DCommands.count, encoder: encoder)
        clearDeferredCommands()
    }

    /// 記録済み 2D コマンドの指定レンジを再投入します（#71・宿題①）。
    /// run（呼び出し順の連続する 2D 区間）単位で呼び、3D の再生と交互に合成する。
    /// レンジ消費後のクリアは呼び出し側（`SketchContext.replayDeferredMain`）が行う。
    func replayForegroundRange(_ range: Range<Int>, encoder: MTLRenderCommandEncoder) {
        let clamped = range.clamped(to: 0..<deferred2DCommands.count)
        for slot in deferred2DCommands[clamped] {
            encode(slot.command, into: encoder)
        }
    }

    /// 記録済み 2D コマンドを破棄します（再生完了後に呼ぶ）。
    func clearDeferredCommands() {
        deferred2DCommands.removeAll(keepingCapacity: true)
    }

    /// 遅延コマンドを「記録（積む）」または「即時エンコード」へ振り分ける（#71）。
    /// 遅延モードでは呼び出し順 seq を付けて積み、そうでなければ即座にエンコードする。
    func emit(_ command: Deferred2DCommand) {
        if isDeferring {
            deferred2DCommands.append(Deferred2DSlot(seq: seqProvider?() ?? 0, command: command))
        } else if let encoder = encoder {
            encode(command, into: encoder)
        }
    }

    /// 遅延コマンド1件を指定エンコーダへ実エンコードする（#71）。
    /// 頂点バッファ・投影行列・デプスステンシルステートはフレーム内で安定な Canvas2D の状態を使う。
    ///
    /// パイプラインはコマンドが持つキーから引くだけで、`currentBlendMode` のような
    /// 可変状態は参照しない（#646）。記録時と再生時で結果が食い違わないための性質。
    func encode(_ command: Deferred2DCommand, into encoder: MTLRenderCommandEncoder) {
        switch command {
        case .colorBatch(let key, let vertexStart, let vertexCount, let shaderParams):
            guard let pipeline = pipelineStore.state(for: key) else { return }
            encoder.setRenderPipelineState(pipeline)
            if let depthState = depthStencilState { encoder.setDepthStencilState(depthState) }
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            var p = projectionMatrix
            encoder.setVertexBytes(&p, length: MemoryLayout<float4x4>.size, index: 1)
            bindShaderResources(key, params: shaderParams, on: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: vertexStart, vertexCount: vertexCount)

        case .texturedBatch(let key, let vertexStart, let vertexCount, let texture, let shaderParams):
            guard let texPipeline = pipelineStore.state(for: key) else { return }
            encoder.setRenderPipelineState(texPipeline)
            if let depthState = depthStencilState { encoder.setDepthStencilState(depthState) }
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(texturedVertexBuffer, offset: 0, index: 0)
            var p = projectionMatrix
            encoder.setVertexBytes(&p, length: MemoryLayout<float4x4>.size, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            bindShaderResources(key, params: shaderParams, on: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: vertexStart, vertexCount: vertexCount)

        case .instancedBatch(
            let key, let shape, let instanceBuffer, let instanceOffset, let instanceCount,
            let shaderParams):
            guard let pipeline = pipelineStore.state(for: key) else { return }
            let (meshBuffer, meshVertexCount) = unitMeshFor(shape)
            encoder.setRenderPipelineState(pipeline)
            if let depthState = depthStencilState { encoder.setDepthStencilState(depthState) }
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(meshBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(instanceBuffer, offset: instanceOffset, index: 6)
            var p = projectionMatrix
            encoder.setVertexBytes(&p, length: MemoryLayout<float4x4>.size, index: 1)
            bindShaderResources(key, params: shaderParams, on: encoder)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0,
                vertexCount: meshVertexCount, instanceCount: instanceCount)

        case .massiveCircles(
            let key, let dataBuffer, let byteOffset, let count, let transform, let shaderParams):
            guard let pipeline = pipelineStore.state(for: key) else { return }
            encoder.setRenderPipelineState(pipeline)
            bindShaderResources(key, params: shaderParams, on: encoder)
            if let depthState = depthStencilState { encoder.setDepthStencilState(depthState) }
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(unitCircleBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(dataBuffer, offset: byteOffset, index: 6)
            var p = projectionMatrix
            var t = transform
            encoder.setVertexBytes(&p, length: MemoryLayout<float4x4>.size, index: 1)
            encoder.setVertexBytes(&t, length: MemoryLayout<float4x4>.size, index: 2)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0,
                vertexCount: unitCircleVertexCount, instanceCount: count)

        case .setScissor(let rect):
            if let rect = rect {
                encoder.setScissorRect(rect)
            } else {
                encoder.setScissorRect(
                    MTLScissorRect(x: 0, y: 0, width: Int(width), height: Int(height)))
            }
        }
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

    // MARK: - カスタムシェーダ（#647 / Epic #291 E2）

    /// 以降の 2D 描画にカスタムフラグメントシェーダを適用します。
    ///
    /// 呼ぶたびに保留中のバッチをフラッシュします。``Shader2D/setParameters(_:)`` の値は
    /// バッチが確定した時点のものが焼き込まれるため、図形ごとにパラメータを変えたいときは
    /// `setParameters()` のあとにこのメソッドを呼び直してください。
    ///
    /// - Parameter shader: 適用するシェーダ。
    public func shader(_ shader: Shader2D) {
        flush()
        currentShader = shader
        currentShaderParams = shader.parameters
        pipelineStore.register(shader)
    }

    /// カスタムシェーダを解除し、組み込みシェーダへ戻します。
    public func resetShader() {
        guard currentShader != nil else { return }
        flush()
        currentShader = nil
        currentShaderParams = nil
    }

    /// 記録時にパイプラインキーを確定させます（#646 の性質を保つ入口）。
    ///
    /// カスタムシェーダ適用中の分離可能ブレンドモード（`.multiply` / `.screen` /
    /// `.subtract` / `.lightest` / `.darkest` / `.difference` / `.exclusion`）は `.alpha` へ
    /// 正規化します。これらは `float4 dest [[color(0)]]` を読む専用フラグメントで実装されていて
    /// カスタムフラグメントと原理的に排他だからです（#647 の規約）。正規化を**記録時**に
    /// 行うのは、コマンド列が「実際にどう描かれたか」をそのまま語るようにするためです。
    func pipelineKey(_ kind: Canvas2DPipelineKind, blend: BlendMode) -> Canvas2DPipelineKey {
        guard let shader = currentShader else { return Canvas2DPipelineKey(kind, blend) }
        guard blend.requiresFramebufferFetch else {
            return Canvas2DPipelineKey(kind, blend, shader: shader.id)
        }
        if !didWarnBlendFallback {
            didWarnBlendFallback = true
            metaphorAlert("""
            blendMode(.multiply / .screen / .subtract / .lightest / .darkest / \
            .difference / .exclusion) はカスタム 2D シェーダと同時には使えません\
            （フレームバッファフェッチ用の組み込みフラグメントで実装されているため）。\
            通常のアルファブレンドで描画します。
            """)
        }
        return Canvas2DPipelineKey(kind, .alpha, shader: shader.id)
    }

    /// 記録中のバッチへ焼き込むカスタムシェーダのパラメータ。適用中でなければ nil。
    ///
    /// **バッチの先頭で取り込む**（flush 時点の ``Shader2D/parameters`` を読むのではなく）。
    /// flush 時点で読むと、`setParameters()` → `shader()` の順で書いたコードで
    /// 「バッチを閉じる直前に新しい値へ差し替わる」ため、直前のバッチまで新しい値で
    /// 描かれてしまう。バッチ先頭で取り込めば、どちらの順序で書いても
    /// 「その図形を描いた時点の値」になる。
    private(set) var currentShaderParams: [UInt8]?

    /// 空のバッチへ最初の要素を積む直前に呼び、適用中シェーダのパラメータを取り込みます。
    /// - Parameter isEmpty: 対象バッチが空（＝これが先頭要素）かどうか。
    func captureShaderParams(ifBatchEmpty isEmpty: Bool) {
        guard isEmpty, let shader = currentShader else { return }
        currentShaderParams = shader.parameters
    }

    /// 再生時にフラグメントへ渡す組み込み uniform を組み立てます。
    /// 解像度とフレーム数は Canvas2D 自身が持ち、時間とマウスは注入フックから受け取ります。
    private func makeShaderUniforms() -> Canvas2DShaderUniforms {
        let inputs = shaderInputs?()
        return Canvas2DShaderUniforms(
            resolution: SIMD2<Float>(width, height),
            mouse: inputs?.mouse ?? SIMD2<Float>(0, 0),
            time: inputs?.time ?? 0,
            frameCount: inputs?.frameCount ?? UInt32(truncatingIfNeeded: frameCounter)
        )
    }

    /// カスタムシェーダ適用中のフラグメント資源をバインドします。
    /// 組み込み uniform は `buffer(3)`、ユーザーパラメータは `buffer(4)`
    /// （3D の ``CustomMaterial`` と同じ index に揃えています）。
    private func bindShaderResources(
        _ key: Canvas2DPipelineKey, params: [UInt8]?, on encoder: MTLRenderCommandEncoder
    ) {
        guard key.shader != nil else { return }
        var uniforms = makeShaderUniforms()
        encoder.setFragmentBytes(
            &uniforms, length: MemoryLayout<Canvas2DShaderUniforms>.stride, index: 3)
        if var bytes = params, !bytes.isEmpty {
            encoder.setFragmentBytes(&bytes, length: bytes.count, index: 4)
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

    // MARK: - 2D インスタンスシェイプ描画

    // 現在のインスタンスバッチを GPU に送信
    func flushInstancedBatch() {
        guard instanceBatcher2D.instanceCount > 0,
              let batchKey = instanceBatcher2D.currentBatchKey else { return }
        // インスタンスバッチのブレンドモードは蓄積開始時のもの。currentBlendMode ではなく
        // こちらでキーを立てる（blendMode() の切替時に先にフラッシュされるため一致する）。
        // カスタムシェーダも shader() / resetShader() が先にフラッシュするので、
        // 蓄積中のバッチは常に単一のシェーダに属する（BatchKey2D にも入れて二重に守る）。
        let key = pipelineKey(.instanced, blend: batchKey.blendMode)
        guard pipelineStore.state(for: key) != nil else { return }
        guard isDeferring || encoder != nil else { return }

        let instanceBuffer = instanceBatcher2D.currentBuffer
        let instanceOffset = instanceBatcher2D.currentBufferOffset
        let instanceCount = instanceBatcher2D.instanceCount
        let shape = batchKey.shapeType
        instanceBatcher2D.reset()

        emit(.instancedBatch(
            pipeline: key, shape: shape,
            instanceBuffer: instanceBuffer, instanceOffset: instanceOffset,
            instanceCount: instanceCount, shaderParams: currentShaderParams))
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
            blendMode: currentBlendMode,
            shader: currentShader?.id
        )

        // currentTransform * translate(cx,cy) * scale(sx,sy) を float4x4 に変換
        let shapeLocal = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(cx, cy, 1)
        ))
        let combined = currentTransform * shapeLocal
        let transform = Canvas2D.embed2DTransform(combined)

        // カスタムシェーダのパラメータはバッチ先頭で取り込む（#647）
        captureShaderParams(ifBatchEmpty: instanceBatcher2D.instanceCount == 0)

        if !instanceBatcher2D.tryAddInstance(key: key, transform: transform, color: fillColor) {
            flushInstancedBatch()
            captureShaderParams(ifBatchEmpty: true)
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

}
