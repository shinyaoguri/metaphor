import AppKit
import MetalKit

/// マルチウィンドウスケッチ用のセカンダリウィンドウ。
///
/// `Sketch` 内で ``Sketch/createWindow(_:)`` を使って作成します。各ウィンドウは
/// 独自のレンダラー、キャンバス、入力処理を持ちます。描画は ``SketchContext`` を
/// 受け取るクロージャで行います。
///
/// ```swift
/// var preview: SketchWindow?
///
/// func setup() {
///     preview = createWindow(SketchWindowConfig(
///         width: 400, height: 300, title: "Preview"
///     ))
/// }
///
/// func draw() {
///     background(.black)
///     circle(width / 2, height / 2, 200)
///
///     preview?.draw { ctx in
///         ctx.background(0.2)
///         ctx.fill(.red)
///         ctx.circle(200, 150, 100)
///     }
/// }
/// ```
///
/// ## 制御 API
///
/// ``context`` の `loop()` / `noLoop()` / `redraw()` / `frameRate(_:)` / `createCanvas(width:height:)`
/// は、**その窓のレンダーループとキャンバス**に効きます（プライマリには影響しません）。
///
/// ```swift
/// preview?.context.createCanvas(width: 800, height: 600)
/// preview?.context.frameRate(30)   // この窓だけ 30fps
/// preview?.context.noLoop()        // この窓だけ止める
/// preview?.context.redraw()        // 止めたまま 1 枚だけ描く
/// ```
///
/// `createCanvas()` はプライマリの `setup()` から呼ぶのが安全です。この窓自身の描画
/// クロージャの中から呼ぶと、リサイズがそのフレームの完了を待つぶん待たされます。
///
/// ## ヘッドレスモード
///
/// 環境変数 `METAPHOR_VIEWER=1`（`metaphor-cli` のライブビューアが子プロセスへ注入する
/// ヘッドレス指定）で起動した場合、セカンダリウィンドウも **`NSWindow` を作らず**
/// オフスクリーンで描画だけを回します（プライマリと同じ扱い）。``config`` の
/// 出力プラグイン（``SketchWindowConfig/plugins``）があれば、そこへの publish は従来どおり続きます。
@MainActor
public final class SketchWindow {
    // MARK: - Public Properties

    /// ウィンドウ設定。
    public let config: SketchWindowConfig

    /// このウィンドウのレンダリングコンテキスト。
    public private(set) var context: SketchContext

    /// このウィンドウが現在開いているかどうか。
    public private(set) var isOpen: Bool = true

    /// このウィンドウのイベント用入力マネージャ。
    public var input: InputManager { context.input }

    // MARK: - Input Event Closures

    /// このウィンドウでマウスボタンが押された時に呼ばれます。
    public var onMousePressed: ((@MainActor (SketchWindow) -> Void))?

    /// このウィンドウでマウスボタンが離された時に呼ばれます。
    public var onMouseReleased: ((@MainActor (SketchWindow) -> Void))?

    /// このウィンドウでマウスが移動した時に呼ばれます。
    public var onMouseMoved: ((@MainActor (SketchWindow) -> Void))?

    /// このウィンドウでマウスがドラッグされた時に呼ばれます。
    public var onMouseDragged: ((@MainActor (SketchWindow) -> Void))?

    /// このウィンドウでスクロールホイールが使用された時に呼ばれます。
    public var onMouseScrolled: ((@MainActor (SketchWindow) -> Void))?

    /// マウスクリックが完了した時（ドラッグなしの押下→離し）に呼ばれます。
    public var onMouseClicked: ((@MainActor (SketchWindow) -> Void))?

    /// このウィンドウでキーが押された時に呼ばれます。
    public var onKeyPressed: ((@MainActor (SketchWindow) -> Void))?

    /// このウィンドウでキーが離された時に呼ばれます。
    public var onKeyReleased: ((@MainActor (SketchWindow) -> Void))?

    // MARK: - Internal State

    /// ウィンドウが閉じられた際に呼ばれるコールバック（SketchContext が設定）。
    var onWindowClosed: ((@MainActor () -> Void))?

    private let renderer: MetaphorRenderer
    private let isHeadless: Bool
    private var window: NSWindow?
    private var mtkView: MetaphorMTKView?
    private var windowDelegate: WindowDelegate?
    private var drawClosure: ((@MainActor (SketchContext) -> Void))?
    private var prevTime: Float = 0
    private var renderTimer: DispatchSourceTimer?
    /// ``renderTimer`` を `suspend()` した状態かどうか。
    ///
    /// `DispatchSource` の suspend はカウント式なので、二重に掛けると同じ回数 resume するまで
    /// 起き上がらず、掛かったまま解放するとクラッシュします。`noLoop()` / `loop()` の
    /// 往復と teardown が釣り合うよう、`SketchRunner` と同じ形で状態を持ちます。
    private var isRenderTimerSuspended = false
    private var activity: NSObjectProtocol?

    /// このウィンドウが使うカスケード配置のスロット（0 起点）。
    ///
    /// ``SketchContext/createWindow(_:)`` が「いま空いている最小のスロット」を選んで渡します。
    /// ヘッドレスでは配置に使いませんが、値は保持します（テスト用の観測点でもある）。
    let cascadeIndex: Int

    /// ネイティブの `NSWindow` を実際に作ったかどうか（テスト用の観測点）。
    /// ヘッドレスでは `false`。
    var hasNativeWindow: Bool { window != nil }

    // MARK: - Initialization

    /// - Parameters:
    ///   - config: ウィンドウ設定。
    ///   - sharedResources: プライマリと共有する Metal リソース。
    ///   - cascadeIndex: カスケード配置のスロット（0 起点。0 はオフセット無し）。
    ///   - clockOffset: このウィンドウの時計に足す秒数。``SketchContext/createWindow(_:)``
    ///     がプライマリの経過時間を渡し、`context.time` の起点をスケッチ開始時刻へ
    ///     揃えます（#836）。
    ///   - isHeadless: ウィンドウを作らずオフスクリーンで回すか。既定は環境変数
    ///     `METAPHOR_VIEWER` からの解決（テストからの注入用に引数化している）。
    /// - Throws: ``SketchWindowConfig/windowScale`` が 0 以下のとき
    ///   ``MetaphorError/invalidParameter(_:)``。キャンバス寸法が範囲外のときは
    ///   ``MetaphorRenderer`` 経由で ``MetaphorError/textureCreationFailed(width:height:format:)``。
    init(
        config: SketchWindowConfig,
        sharedResources: SharedMetalResources,
        cascadeIndex: Int = 0,
        clockOffset: Double = 0,
        isHeadless: Bool = SketchWindow.resolveHeadless(env: ProcessInfo.processInfo.environment)
    ) throws {
        // windowScale の検証（#842）。0 だと 0×0 pt のウィンドウが「開いている」ことになり、
        // 見えないのに isOpen == true のまま残る。キャンバス側（テクスチャ）の寸法は
        // 正常なので TextureManager のガードには掛からず、ここでしか止められない。
        guard config.windowScale > 0 else {
            throw MetaphorError.invalidParameter(
                "windowScale must be greater than 0 (got \(config.windowScale))"
            )
        }

        self.config = config
        self.cascadeIndex = cascadeIndex
        self.isHeadless = isHeadless

        let renderer = try MetaphorRenderer(
            sharedResources: sharedResources,
            width: config.width,
            height: config.height
        )
        // レンダーループを組む前に時計を合わせる。setupRenderLoop() のタイマーは
        // `deadline: .now()` で resume するので、生成後に外から入れると最初の
        // 1 フレームだけ 0 起点で描かれてしまう（#836）。
        renderer.clockOffset = clockOffset
        self.renderer = renderer

        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)

        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }

        self.context = SketchContext(
            renderer: renderer,
            canvas: canvas,
            canvas3D: canvas3D,
            input: renderer.input
        )

        // 時計を引き継いだぶん、deltaTime の起点も寄せる。合わせないと最初の 1 フレームの
        // deltaTime が「スケッチ開始からの経過時間まるごと」になり、それを積分に使う側が
        // 1 回で吹き飛ぶ（SketchRunner が preserveClock で FrameClock を resync するのと同じ理屈。#793）
        self.prevTime = Float(clockOffset)

        // 出力（Syphon 等）は登録済み provider の走査で決まる（Core は出力実装を名指ししない）。
        // 出力 target 未リンク時は何も返らず no-op。レンダーループの駆動方法は、config.plugins と
        // 出力の要件を集計してから決める（プラグイン生成より前 = SketchRunner と同じ順序）。
        let outputs = MetaphorOutputProviders.makeOutputs(
            context: MetaphorOutputContext(
                scope: .window(config),
                environment: ProcessInfo.processInfo.environment,
                isHeadless: isHeadless
            )
        )
        let loopMode = Self.resolveLoopMode(
            config: config,
            requirements: Self.aggregateRequirements(config: config, outputs: outputs),
            isHeadless: isHeadless
        )

        setupWindow()
        setupRenderLoop(loopMode)
        connectControls()
        connectInput()

        // config のプラグインはこのウィンドウ専用のレンダラーへ（プライマリとは独立。
        // セカンダリには Sketch が無いので onAttach(renderer:) のみ）。
        for factory in config.plugins {
            renderer.addPlugin(factory.create())
        }
        for output in outputs {
            renderer.addPlugin(output.plugin)
        }
    }

    // MARK: - Drawing API

    /// このウィンドウの描画クロージャを設定します。
    ///
    /// クロージャは保存され、このウィンドウのレンダーループが毎フレーム実行します
    /// （呼び出しごとに即時描画されるわけではありません）。``onDraw(_:)`` と同じ
    /// 保存セマンティクスで、こちらはウィンドウが閉じている場合に無視される点だけが
    /// 異なります。毎フレーム同じクロージャを再設定しても害はありませんが、
    /// 1 回の設定で十分です。
    ///
    /// - Parameter closure: 毎フレーム描画操作を行うクロージャ。
    public func draw(_ closure: @escaping @MainActor (SketchContext) -> Void) {
        guard isOpen else { return }
        drawClosure = closure
    }

    /// 毎フレーム自動実行される永続的な描画クロージャを設定します。
    ///
    /// ``draw(_:)`` と同じ保存セマンティクスです（どちらも同じスロットに保存され、
    /// フレームを跨いで永続します）。こちらはウィンドウの開閉状態に関わらず設定します。
    ///
    /// - Parameter closure: 毎フレーム描画操作を行うクロージャ。
    public func onDraw(_ closure: @escaping @MainActor (SketchContext) -> Void) {
        drawClosure = closure
    }

    /// このウィンドウを閉じリソースを解放します。
    public func close() {
        guard isOpen else { return }
        if let window {
            // NSWindow.close() が WindowDelegate（windowWillClose）経由で
            // handleWindowClose() を呼び、共通の後始末を行う。UI の閉じるボタンと
            // 同じ単一の teardown 経路に集約する
            window.close()
        } else {
            handleWindowClose()
        }
    }

    // MARK: - Environment Resolution

    /// ヘッドレス（ウィンドウを開かない）で動かすかを環境変数から解決します。
    ///
    /// `METAPHOR_VIEWER=1` は `metaphor-cli` のライブビューアが子プロセスへ注入する
    /// ヘッドレス指定で、プライマリ（``SketchRunner``）と同じ変数を見ます。
    ///
    /// - Parameter env: 参照する環境変数（テストから注入可能）。
    /// - Returns: ヘッドレスなら `true`。
    nonisolated static func resolveHeadless(env: [String: String]) -> Bool {
        env["METAPHOR_VIEWER"] == "1"
    }

    /// 実効レンダーループモードを解決します
    /// （純粋関数。``RenderLoopMode/resolve(requested:fps:requirements:isHeadless:)`` に委譲）。
    ///
    /// - ヘッドレスでは `MTKView` が無くディスプレイリンクを駆動できないため、常にタイマー。
    /// - `.displayLink` のままでも、``PluginRequirements/externalRenderLoop`` を宣言する
    ///   プラグインか出力（Syphon 等）があれば出力の安定のためタイマーへ切り替える（従来どおり）。
    ///
    /// - Parameters:
    ///   - config: ウィンドウ設定。
    ///   - requirements: `aggregateRequirements(config:outputs:)` の結果。
    ///   - isHeadless: ヘッドレスかどうか。
    /// - Returns: 実際に使うレンダーループモード。
    nonisolated static func resolveLoopMode(
        config: SketchWindowConfig, requirements: PluginRequirements, isHeadless: Bool
    ) -> RenderLoopMode {
        RenderLoopMode.resolve(
            requested: config.renderLoopMode, fps: config.fps,
            requirements: requirements, isHeadless: isHeadless
        )
    }

    /// ``SketchWindowConfig/plugins`` のファクトリと、出力 provider が返した出力の要件の和を取ります。
    nonisolated static func aggregateRequirements(
        config: SketchWindowConfig, outputs: [MetaphorOutputProviders.ResolvedOutput]
    ) -> PluginRequirements {
        var requirements = PluginRequirements()
        for factory in config.plugins { requirements.formUnion(factory.requirements) }
        for output in outputs { requirements.formUnion(output.requirements) }
        return requirements
    }

    // MARK: - Window Placement

    /// カスケードスロットに対応する配置オフセット（ポイント）。
    ///
    /// スロット 0 は中央（オフセット無し）で、1 枚増えるごとに右下へ 30pt ずらします。
    ///
    /// - Parameter slot: カスケードスロット（0 起点）。
    /// - Returns: 中央からずらす量（ポイント）。
    nonisolated static func cascadeOffset(slot: Int) -> CGFloat {
        CGFloat(30 * slot)
    }

    // MARK: - Private Setup

    private func setupWindow() {
        // ヘッドレスではネイティブウィンドウも `MTKView` も作らない（プライマリと同じ扱い）。
        // 描画は setupRenderLoop() のタイマーが `renderFrame()` を回して継続する。
        if isHeadless { return }

        let windowWidth = CGFloat(Float(config.width) * config.windowScale)
        let windowHeight = CGFloat(Float(config.height) * config.windowScale)

        // 生成は SketchWindowFactory へ集約（isReleasedWhenClosed = false を含む。#835）。
        let win = SketchWindowFactory.makeWindow(
            contentSize: NSSize(width: windowWidth, height: windowHeight),
            title: config.title,
            aspectRatio: NSSize(width: config.width, height: config.height)
        )

        // ウィンドウを重ならないようにカスケード。スロットは開いている枚数に連動し、
        // 閉じれば空く（単調増加のカウンタだと開き直すたびに 30pt ずつ流れた。#837）
        let offset = Self.cascadeOffset(slot: cascadeIndex)
        win.setFrameOrigin(NSPoint(
            x: win.frame.origin.x + offset,
            y: win.frame.origin.y - offset
        ))

        let mtkView = MetaphorMTKView()
        mtkView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoresizingMask = [.width, .height]
        renderer.configure(view: mtkView)
        win.contentView = mtkView

        // クローズ処理用のウィンドウデリゲート
        let delegate = WindowDelegate { [weak self] in
            self?.handleWindowClose()
        }
        win.delegate = delegate
        self.windowDelegate = delegate

        self.window = win
        self.mtkView = mtkView

        win.makeKeyAndOrderFront(nil)
    }

    /// - Parameter loopMode: `resolveLoopMode(config:requirements:isHeadless:)` で決めた
    ///   実効モード（ヘッドレスは常にタイマー / 外部ループを要する出力があればタイマー）。
    private func setupRenderLoop(_ loopMode: RenderLoopMode) {
        switch loopMode {
        case .displayLink:
            mtkView?.preferredFramesPerSecond = config.fps
            mtkView?.isPaused = false

        case .timer(let fps):
            renderer.useExternalRenderLoop = true

            mtkView?.preferredFramesPerSecond = fps
            mtkView?.isPaused = false

            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Timer-based render loop requires consistent frame rate"
            )

            let interval = 1.0 / Double(max(fps, 1))
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                dispatchPrecondition(condition: .onQueue(.main))
                MainActor.assumeIsolated {
                    self?.renderer.renderFrame()
                }
            }
            timer.resume()
            renderTimer = timer
        }

        renderer.onDraw = { [weak self] encoder, time in
            guard let self, let closure = self.drawClosure else { return }
            let t = Float(time)
            let dt = t - self.prevTime
            self.prevTime = t
            self.context.beginFrame(encoder: encoder, time: t, deltaTime: dt)
            closure(self.context)
            self.context.endFrame()
        }

        renderer.onAfterDraw = { [weak self] commandBuffer in
            guard let self else { return }
            self.context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }

        // 記録→shadow→再生の経路: 影オン（#70）またはコマンド記録 opt-in（#71）で使う。
        renderer.shadowDeferActive = { [weak self] in
            self?.context.canvas3D.shouldRecordMainPass ?? false
        }
        renderer.onRecordFrame = { [weak self] time in
            guard let self, let closure = self.drawClosure else { return }
            let t = Float(time)
            let dt = t - self.prevTime
            self.prevTime = t
            self.context.beginRecordingFrame(time: t, deltaTime: dt)
            closure(self.context)
            self.context.endRecordingFrame()
        }
        renderer.onReplayMain = { [weak self] encoder, time in
            self?.context.replayDeferredMain(encoder: encoder, time: Float(time))
        }
    }

    /// ``SketchContext`` の制御 API（`loop()` / `noLoop()` / `redraw()` / `frameRate()` /
    /// `createCanvas()`）をこの窓のレンダラへ配線します（#857）。
    ///
    /// `SketchContext` はハンドラが `nil` なら状態だけ変えて黙って返るので、配線が無いと
    /// 呼び出しはすべて no-op に落ちます（`SketchView` 経路の #808 / #828 と同じ穴）。
    ///
    /// 宛先は**この窓のレンダーループ**で、`SketchView` 経路の写経では足りません。
    /// `resolveLoopMode(config:requirements:isHeadless:)` のとおり `SketchWindow` は 2 系統を持ち、
    /// ヘッドレスと、外部ループを要する出力（Syphon 等のプラグイン）ありは**タイマー駆動**になります。
    /// タイマーは `MTKView.isPaused` では止まらず（そもそもヘッドレスでは `mtkView` が `nil`）、
    /// フレームレートも `preferredFramesPerSecond` ではなくタイマーの再スケジュールで変わります。
    /// そのため `SketchRunner` と同じく `renderTimer` の有無で宛先を分けます。
    private func connectControls() {
        context.onLoop = { [weak self] in
            guard let self else { return }
            // 時計（renderer.elapsedTime）は止めている間も進むので、再開の前に deltaTime の
            // 起点を寄せ直す。寄せないと再開後の最初のフレームへ「止めていた実時間まるごと」が
            // 渡り、それを積分に使う側が 1 回で吹き飛ぶ（#793。SketchRunner.handleLoop と同じ）。
            self.prevTime = Float(self.renderer.elapsedTime)
            if let renderTimer = self.renderTimer {
                self.resumeRenderTimerIfNeeded(renderTimer)
            } else {
                self.mtkView?.isPaused = false
            }
            self.renderer.notifyPluginsStart()
        }

        context.onNoLoop = { [weak self] in
            guard let self else { return }
            if let renderTimer = self.renderTimer {
                self.suspendRenderTimerIfNeeded(renderTimer)
            } else {
                self.mtkView?.isPaused = true
            }
            self.renderer.notifyPluginsStop()
        }

        context.onRedraw = { [weak self] in
            guard let self else { return }
            if self.renderTimer != nil {
                // タイマーモードは useExternalRenderLoop = true で、`MTKView.draw()` は
                // 再レンダリングせずブリットするだけ。先にオフスクリーンを 1 枚描く。
                // ヘッドレスは mtkView が無いので、この 1 回がそのまま redraw の実体になる。
                self.renderer.renderFrame()
            }
            // ディスプレイリンクモード: draw(in:) が renderFrame() + ブリットを 1 回で行う。
            self.mtkView?.draw()
        }

        context.onFrameRate = { [weak self] fps in
            guard let self else { return }
            // 0 以下のクランプは全経路で共通（#358）。
            let clampedFPS = clampedFrameRate(fps)
            self.renderer.targetFPS = clampedFPS
            if let renderTimer = self.renderTimer {
                let interval = 1.0 / Double(clampedFPS)
                renderTimer.schedule(
                    deadline: .now(), repeating: interval, leeway: .milliseconds(1)
                )
            } else {
                self.mtkView?.preferredFramesPerSecond = clampedFPS
            }
        }

        context.onCreateCanvas = { [weak self] width, height in
            self?.handleCreateCanvas(width: width, height: height)
        }
    }

    /// テクスチャ・キャンバスを新しいキャンバスサイズに合わせて再構築します（#857）。
    ///
    /// `SketchRunner.handleCreateCanvas` と同じ手順ですが、**窓を中央へ寄せ直しません**。
    /// セカンダリ窓は開いている枚数に応じてカスケード配置されており（#837）、
    /// `center()` を呼ぶとそのオフセットが消えて窓同士が重なるためです。
    ///
    /// - Note: `MetaphorRenderer.resizeCanvas` はインフライトフレームを枯らすため
    ///   `inflightSemaphore` を 3 つ取りに行きます。この窓自身の描画クロージャの**中**から
    ///   呼ぶと、そのフレームが 1 つ掴んだままで取り切れないので、`SketchContext.createCanvas`
    ///   が警告を出して弾きます（#856）。プライマリの `setup()` から
    ///   `window.context.createCanvas(...)` と呼ぶのが安全な呼び出し位置です（#828 と同じ性質）。
    ///
    /// - Parameters:
    ///   - width: 新しいキャンバスの幅（ピクセル単位）。
    ///   - height: 新しいキャンバスの高さ（ピクセル単位）。
    private func handleCreateCanvas(width: Int, height: Int) {
        renderer.resizeCanvas(width: width, height: height)

        guard let newCanvas = try? Canvas2D(renderer: renderer),
              let newCanvas3D = try? Canvas3D(renderer: renderer) else {
            metaphorWarning("createCanvas(\(width), \(height)) failed to rebuild canvases")
            return
        }
        newCanvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        context.rebuildCanvas(canvas: newCanvas, canvas3D: newCanvas3D)

        // 窓を持つときは中身の比率にも追随させる（ヘッドレスでは window が nil で no-op）。
        let windowWidth = CGFloat(Float(width) * config.windowScale)
        let windowHeight = CGFloat(Float(height) * config.windowScale)
        window?.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window?.contentAspectRatio = NSSize(width: width, height: height)
    }

    private func suspendRenderTimerIfNeeded(_ timer: DispatchSourceTimer) {
        guard !isRenderTimerSuspended else { return }
        timer.suspend()
        isRenderTimerSuspended = true
    }

    private func resumeRenderTimerIfNeeded(_ timer: DispatchSourceTimer) {
        guard isRenderTimerSuspended else { return }
        timer.resume()
        isRenderTimerSuspended = false
    }

    private func connectInput() {
        let input = renderer.input
        input.onMousePressed = { [weak self] _, _, _ in
            guard let self else { return }
            self.onMousePressed?(self)
        }
        input.onMouseReleased = { [weak self] _, _, _ in
            guard let self else { return }
            self.onMouseReleased?(self)
        }
        input.onMouseMoved = { [weak self] _, _ in
            guard let self else { return }
            self.onMouseMoved?(self)
        }
        input.onMouseDragged = { [weak self] _, _ in
            guard let self else { return }
            self.onMouseDragged?(self)
        }
        input.onMouseScrolled = { [weak self] _, _ in
            guard let self else { return }
            self.onMouseScrolled?(self)
        }
        input.onMouseClicked = { [weak self] _, _, _ in
            guard let self else { return }
            self.onMouseClicked?(self)
        }
        input.onKeyDown = { [weak self] _, _ in
            guard let self else { return }
            self.onKeyPressed?(self)
        }
        input.onKeyUp = { [weak self] _ in
            guard let self else { return }
            self.onKeyReleased?(self)
        }
    }

    /// ウィンドウクローズ時の共通 teardown。UI の閉じるボタン（WindowDelegate 経由）と
    /// プログラム的な ``close()`` の両方がここへ集約される。
    private func handleWindowClose() {
        guard isOpen else { return }
        isOpen = false
        stopRenderTimer()
        // プラグイン解放（onStop → onDetach）。出力プラグイン（Syphon 等）はここでサーバーを停止し、
        // 閉じたウィンドウの出力が外部に残るのを防ぐ。
        // 以前は UI の閉じるボタン経由でこの shutdown が呼ばれていなかった。
        renderer.shutdown()
        drawClosure = nil
        mtkView = nil
        window = nil
        windowDelegate = nil
        context.performCleanup()
        onWindowClosed?()
        onWindowClosed = nil
    }

    private func stopRenderTimer() {
        if let renderTimer {
            renderTimer.cancel()
            // cancel 後に resume するのは、suspend されたまま（noLoop 中に閉じた場合など）の
            // DispatchSource は解放時にクラッシュするため — cancel 済みなので resume で
            // イベントハンドラが再発火することはなく、suspend カウントだけが 0 に戻る
            // （`SketchRunner.applicationWillTerminate` と対称）。
            resumeRenderTimerIfNeeded(renderTimer)
            self.renderTimer = nil
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    // MARK: - Window Delegate

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: @MainActor () -> Void

        init(onClose: @escaping @MainActor () -> Void) {
            self.onClose = onClose
        }

        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                onClose()
            }
        }
    }
}
