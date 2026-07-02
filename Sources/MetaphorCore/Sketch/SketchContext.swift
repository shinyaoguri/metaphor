import AppKit
import Metal
import simd

/// Sketch 内で使用される描画コンテキストを提供します。
///
/// Canvas2D と Canvas3D の描画メソッドを転送し、時間、入力、フレーム状態の
/// 便利プロパティを公開します。上級ユーザーは `renderer`、`encoder`、
/// `canvas`、`canvas3D` をエスケープハッチとして利用できます。
@MainActor
public final class SketchContext {
    // MARK: - Public Properties

    /// キャンバスの幅（ピクセル単位）。
    public private(set) var width: Float

    /// キャンバスの高さ（ピクセル単位）。
    public private(set) var height: Float

    /// スケッチ開始からの経過時間（秒単位）。
    public var time: Float = 0

    /// 前フレームからの経過時間（秒単位）。
    public var deltaTime: Float = 0

    /// これまでにレンダリングされたフレーム数。
    public var frameCount: Int = 0

    /// マウスとキーボードの状態を管理する入力マネージャ。
    public let input: InputManager

    // MARK: - Escape Hatches

    /// 基盤のレンダラー（上級者向け）。
    public let renderer: MetaphorRenderer

    /// バックグラウンドでの画像/モデル読み込み用の非同期リソースローダー。
    public let resourceLoader: ResourceLoader

    /// 現在のレンダーコマンドエンコーダー。フレーム中のみ有効。
    public var encoder: MTLRenderCommandEncoder? { canvas.currentEncoder }

    /// 2D キャンバス（上級者向け）。
    public private(set) var canvas: Canvas2D

    /// 3D キャンバス（上級者向け）。
    public private(set) var canvas3D: Canvas3D

    // MARK: - Animation Control

    /// 描画ループが現在実行中かどうか。
    public private(set) var isLooping: Bool = true

    /// ループ再開時に呼ばれるコールバック（SketchRunner が設定）。
    var onLoop: (() -> Void)?

    /// ループ停止時に呼ばれるコールバック（SketchRunner が設定）。
    var onNoLoop: (() -> Void)?

    /// 単一フレーム再描画時に呼ばれるコールバック（SketchRunner が設定）。
    var onRedraw: (() -> Void)?

    /// フレームレート変更時に呼ばれるコールバック（SketchRunner が設定）。
    var onFrameRate: ((Int) -> Void)?

    /// アニメーションループを再開します。
    public func loop() {
        guard !isLooping else { return }
        isLooping = true
        onLoop?()
    }

    /// アニメーションループを停止します。
    public func noLoop() {
        guard isLooping else { return }
        isLooping = false
        onNoLoop?()
    }

    /// 単一フレームを描画します（ループ停止時に使用）。
    public func redraw() {
        onRedraw?()
    }

    /// 目標フレームレートを動的に変更します。
    /// - Parameter fps: 目標フレーム毎秒。
    public func frameRate(_ fps: Int) {
        onFrameRate?(fps)
    }

    // MARK: - Cursor Control

    /// マウスカーソルを表示します。
    public func cursor() {
        NSCursor.unhide()
    }

    /// マウスカーソルを非表示にします。
    public func noCursor() {
        NSCursor.hide()
    }

    // MARK: - Cache Management

    /// すべての内部キャッシュ（メッシュ、パイプライン、テクスチャ、フィルター、
    /// テキストアトラス、デプスステンシルステート、ポストプロセスパイプラインなど）を一括クリアします。
    ///
    /// シーン切り替え時や GPU メモリの回収時に呼び出してください。再描画時に
    /// 必要なキャッシュは自動的に再構築されます。
    public func clearCaches() {
        canvas.clearTextCache()
        canvas3D.clearMeshCache()
        canvas3D.clearCustomPipelineCache()
        renderer.imageFilterGPU.clearCache()
        renderer.depthStencilCache.clear()
        renderer.postProcessPipeline?.invalidatePipelines()
        renderer.postProcessPipeline?.invalidateTextures()
    }

    // MARK: - Canvas Resize

    /// キャンバスリサイズ時に呼ばれるコールバック（SketchRunner が設定）。
    var onCreateCanvas: ((Int, Int) -> Void)?

    /// キャンバスサイズを設定します（セットアップ中に呼び出してください）。
    /// - Parameters:
    ///   - width: キャンバスの幅（ピクセル単位）。
    ///   - height: キャンバスの高さ（ピクセル単位）。
    public func createCanvas(width: Int, height: Int) {
        onCreateCanvas?(width, height)
    }

    /// リサイズ後に内部キャンバスを再構築します（内部使用）。
    func rebuildCanvas(canvas: Canvas2D, canvas3D: Canvas3D) {
        self.canvas = canvas
        self.canvas3D = canvas3D
        self.width = canvas.width
        self.height = canvas.height
        wireDrawSeqProviders()
    }

    // MARK: - Tween Manager

    /// 毎フレーム登録済みトゥイーンを自動更新するトゥイーンマネージャ。
    public let tweenManager = TweenManager()

    // MARK: - GUI

    /// イミディエイトモードコントロール用のパラメータ GUI インスタンス。
    public let gui = ParameterGUI()

    // MARK: - Performance HUD

    /// パフォーマンス HUD インスタンス。無効の場合は nil。
    private var performanceHUD: PerformanceHUD?

    /// パフォーマンス HUD オーバーレイを有効にします。
    public func enablePerformanceHUD() {
        if performanceHUD == nil {
            performanceHUD = PerformanceHUD()
        }
    }

    /// パフォーマンス HUD オーバーレイを無効にします。
    public func disablePerformanceHUD() {
        performanceHUD = nil
    }

    // MARK: - Compute State (internal)

    /// 現在のコマンドバッファ。コンピュートフェーズ中のみ有効。
    var _commandBuffer: MTLCommandBuffer?

    /// 遅延生成されるコンピュートコマンドエンコーダー。
    var _computeEncoder: MTLComputeCommandEncoder?

    // MARK: - GIF Export (D-19)

    /// GIF エクスポーターインスタンス。
    public let gifExporter = GIFExporter()

    // MARK: - Orbit Camera (D-20)

    /// オービットカメラインスタンス。
    public let orbitCamera = OrbitCamera()

    // MARK: - Multi-Window

    /// 共有 Metal リソース。プライマリウィンドウ用に SketchRunner が設定。
    var _sharedResources: SharedMetalResources?

    /// これがプライマリスケッチコンテキストかどうか（グローバル経過時間を制御）。
    var isPrimary: Bool = false

    /// このコンテキストから作成されたセカンダリウィンドウ。
    private var secondaryWindows: [SketchWindow] = []

    /// 新しいセカンダリウィンドウを作成します。
    ///
    /// - Parameter config: ウィンドウ設定。
    /// - Returns: 新しい ``SketchWindow`` インスタンス。作成に失敗した場合は `nil`。
    public func createWindow(_ config: SketchWindowConfig = SketchWindowConfig()) -> SketchWindow? {
        guard let shared = _sharedResources else {
            metaphorWarning("Cannot create window: shared resources unavailable")
            return nil
        }

        do {
            let window = try SketchWindow(config: config, sharedResources: shared)
            secondaryWindows.append(window)
            window.onWindowClosed = { [weak self, weak window] in
                guard let self, let window else { return }
                self.secondaryWindows.removeAll { $0 === window }
            }
            return window
        } catch {
            metaphorWarning("Failed to create window: \(error)")
            return nil
        }
    }

    /// すべてのセカンダリウィンドウを閉じリソースを解放します。
    public func closeAllWindows() {
        for window in secondaryWindows {
            window.close()
        }
        secondaryWindows.removeAll()
    }

    // MARK: - Cleanup Hooks

    /// 外部モジュールが登録するクリーンアップハンドラ。
    /// コンテキスト破棄時に呼び出されます。
    private var _cleanupHandlers: [() -> Void] = []

    /// クリーンアップハンドラを登録します。
    /// コンテキスト破棄時に呼び出されます。
    public func addCleanupHandler(_ handler: @escaping () -> Void) {
        _cleanupHandlers.append(handler)
    }

    /// 登録されたクリーンアップハンドラを実行し、リストをクリアします。
    public func performCleanup() {
        for handler in _cleanupHandlers {
            handler()
        }
        _cleanupHandlers.removeAll()
    }

    // MARK: - Initialization

    init(renderer: MetaphorRenderer, canvas: Canvas2D, canvas3D: Canvas3D, input: InputManager) {
        self.renderer = renderer
        self.resourceLoader = ResourceLoader(device: renderer.device)
        self.canvas = canvas
        self.canvas3D = canvas3D
        self.input = input
        self.width = canvas.width
        self.height = canvas.height
        wireDrawSeqProviders()
    }

    // MARK: - Shape Recording Target (#150)

    /// beginShape / beginShape3D のアクティブな記録先。
    /// vertex 系のオーバーロードは引数の数（2D/3D）ではなくこの記録先へ
    /// ルーティングされる（2D 記録中の vertex(x,y,z) が 3D へ誤送出されて
    /// 何も描かれない Processing 経験者の罠を防ぐ）。
    enum ShapeRecordingTarget { case none, twoD, threeD }

    /// 現在アクティブなシェイプ記録先。
    var activeShapeRecording: ShapeRecordingTarget = .none

    // MARK: - Draw Sequence (#71)

    /// draw() 内の 2D/3D 呼び出し順を表す単調シーケンス番号。
    /// `beginFrame` でフレーム頭にリセットされる。
    private var drawSeqCounter: UInt32 = 0

    /// 次の呼び出し順番号を払い出す（呼ぶたびに +1）。
    /// 記録経路で各 2D/3D コマンドに付与し、再生時の seq 昇順マージに使う。
    func nextDrawSeq() -> UInt32 {
        defer { drawSeqCounter &+= 1 }
        return drawSeqCounter
    }

    /// 両 Canvas に seq 払い出しクロージャを注入する。
    /// Canvas は Context を直接参照せず、このクロージャ経由でのみ seq を得る（依存方向の維持）。
    /// `rebuildCanvas` での再構築時にも呼ぶ。
    private func wireDrawSeqProviders() {
        canvas.seqProvider = { [weak self] in self?.nextDrawSeq() ?? 0 }
        canvas3D.seqProvider = { [weak self] in self?.nextDrawSeq() ?? 0 }
        // 3D 記録の直前に 2D 保留バッチを確定し、呼び出し順 seq を保つ（#71・宿題①）。
        canvas3D.flushPending2D = { [weak self] in
            guard let self, self.canvas.isDeferring else { return }
            self.canvas.flush()
        }
    }

    // MARK: - Compute Frame Management (internal)

    /// コンピュートフェーズを開始します。
    func beginCompute(commandBuffer: MTLCommandBuffer, time: Float, deltaTime: Float) {
        self._commandBuffer = commandBuffer
        self.time = time
        self.deltaTime = deltaTime
    }

    /// コンピュートフェーズを終了し、エンコーダーが作成されていた場合はファイナライズします。
    func endCompute() {
        _computeEncoder?.endEncoding()
        _computeEncoder = nil
        _commandBuffer = nil
    }

    // MARK: - Frame Management (internal)

    func beginFrame(
        encoder: MTLRenderCommandEncoder?, time: Float, deltaTime: Float,
        preciseTime: Double? = nil
    ) {
        self.time = time
        if isPrimary {
            // millis() 用は Double 精度で保持（Float 経由だと長時間実行で ms 分解能が落ちる）
            _sketchElapsedTime = preciseTime ?? Double(time)
        }
        self.deltaTime = deltaTime
        self.frameCount += 1
        drawSeqCounter = 0  // 呼び出し順番号をフレーム頭でリセット（#71）
        tweenManager.update(deltaTime)
        canvas3D.begin(encoder: encoder, time: time, bufferIndex: renderer.frameBufferIndex)
        canvas.begin(encoder: encoder, bufferIndex: renderer.frameBufferIndex)
    }

    // MARK: - シャドウ同一フレーム化（#70）の記録/再生フレーム

    /// シャドウ遅延経路でこのフレームを「記録モード」で開始します。
    /// メインエンコーダはまだ無く、3D は記録、2D は前景キューへ遅延されます。
    func beginRecordingFrame(time: Float, deltaTime: Float) {
        canvas.isDeferring = true
        beginFrame(encoder: nil, time: time, deltaTime: deltaTime)
    }

    /// 記録モードのフレームを終了します（2D は前景キューへ flush 済みになる）。
    func endRecordingFrame() {
        endFrame()
        canvas.isDeferring = false
    }

    /// 記録済みの 2D/3D を **呼び出し順（seq 昇順）** で単一メインパスへ再生します（#71・宿題①）。
    ///
    /// 3D の `DrawCall3D` と 2D の `Deferred2DSlot` を seq でマージし、隣接同種を run に
    /// まとめて Canvas へ範囲再投入する。3D は深度 readWrite、2D は深度 disabled で、
    /// 呼び出し順に投入することで「3D 背後の 2D は先に描かれ後続 3D が上に重なる／前面 2D は
    /// 最後に上書き」が自然に成立する（共有深度1枚・追加レンダーパスなし）。
    func replayDeferredMain(encoder: MTLRenderCommandEncoder, time: Float) {
        let threeDSeqs = canvas3D.recordedDrawCalls.map(\.seq)
        let twoDSeqs = canvas.deferred2DCommands.map(\.seq)
        let order = DrawStreamMerge.mergeOrder(threeDSeqs: threeDSeqs, twoDSeqs: twoDSeqs)

        canvas3D.beginReplay(encoder: encoder)
        var i = 0
        while i < order.count {
            switch order[i] {
            case .threeD(let start):
                // 連続する 3D run の終端を探す（マージ結果はストリーム内で連番）。
                var end = start
                var j = i + 1
                while j < order.count, case .threeD(let idx) = order[j] {
                    end = idx
                    j += 1
                }
                canvas3D.replayRecordedRange(start..<(end + 1))
                i = j
            case .twoD(let start):
                var end = start
                var j = i + 1
                while j < order.count, case .twoD(let idx) = order[j] {
                    end = idx
                    j += 1
                }
                canvas.replayForegroundRange(start..<(end + 1), encoder: encoder)
                i = j
            }
        }
        canvas3D.endReplay()
        canvas.clearDeferredCommands()
    }

    func endFrame() {
        // ParameterGUI の入力エッジ検出状態を更新（ユーザーが updateInput を
        // 呼ばなくても toggle のクリック判定が正しく動くよう自動配線）
        gui.updateInput(input: input)

        // パフォーマンス HUD オーバーレイ（canvas.end() の前に描画し最前面に表示）
        if let hud = performanceHUD {
            hud.update(deltaTime: deltaTime)
            hud.updateGPUTime(start: renderer.lastGPUStartTime, end: renderer.lastGPUEndTime)
            hud.draw(canvas: canvas, width: Float(renderer.textureManager.width), height: Float(renderer.textureManager.height))
        }
        canvas3D.end()
        canvas.end()

        // このフレームの draw() で background() が呼ばれたかに基づいて
        // 次フレームの loadAction を決定。呼ばれていなければ前フレームの
        // 内容を保持（Processing の動作）。
        let shouldClearNext = canvas.backgroundCalledThisFrame
        renderer.textureManager.setShouldClear(shouldClearNext)
        canvas.frameWillClear = shouldClearNext
        // 最初の background() 呼び出し後、レンダーパスディスクリプタの clearColor は
        // ユーザーが指定した色と一致します。以降のフレームではこの clearColor で
        // エンコーダーが作成されるため、background() の最適化（Metal のクリアに
        // 任せてクワッド描画をスキップ）が安全です。
        if shouldClearNext {
            canvas.markPendingClearColorApplied()
        }

        // GIF キャプチャは renderer.onCaptureOutput（beginGIFRecord で配線）に
        // 移動した。endFrame 時点ではメインコマンドバッファが未コミットのため、
        // ここで独自バッファをコミットすると 1 フレーム前の内容
        // （しかもポストエフェクト適用前の colorTexture）を読んでしまう。
    }
}
