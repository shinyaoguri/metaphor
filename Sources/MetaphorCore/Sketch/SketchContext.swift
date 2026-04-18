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
        isLooping = true
        onLoop?()
    }

    /// アニメーションループを停止します。
    public func noLoop() {
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

    /// すべての内部キャッシュ（メッシュ、パイプライン、テクスチャ、フィルターキャッシュ）をクリアします。
    ///
    /// シーン切り替え時や GPU メモリの回収時に呼び出してください。
    public func clearCaches() {
        canvas3D.clearMeshCache()
        canvas3D.clearCustomPipelineCache()
        renderer.imageFilterGPU.clearCache()
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

    func beginFrame(encoder: MTLRenderCommandEncoder, time: Float, deltaTime: Float) {
        self.time = time
        if isPrimary {
            _sketchElapsedTime = time
        }
        self.deltaTime = deltaTime
        self.frameCount += 1
        tweenManager.update(deltaTime)
        canvas3D.begin(encoder: encoder, time: time, bufferIndex: renderer.frameBufferIndex)
        canvas.begin(encoder: encoder, bufferIndex: renderer.frameBufferIndex)
    }

    func endFrame() {
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
            canvas.clearColorApplied = true
        }

        // GIF フレームキャプチャ
        captureGIFFrame()
    }
}
