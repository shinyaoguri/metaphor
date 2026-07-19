import AppKit
import MetalKit

/// スケッチのライフサイクルを管理します。
///
/// `NSApplicationDelegate` として動作し、プログラム的にウィンドウ、
/// `MTKView`、レンダラーを構築します。ユーザーがこのクラスを
/// 直接操作することはありません。
@MainActor
final class SketchRunner: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var mtkView: MetaphorMTKView?
    private var renderer: MetaphorRenderer?
    private var canvas: Canvas2D?
    private var canvas3D: Canvas3D?
    private var context: SketchContext?
    private var sketchRef: (any Sketch)?
    private var renderTimer: DispatchSourceTimer?
    private var isRenderTimerSuspended = false
    private var activity: NSObjectProtocol?
    private var sharedResources: SharedMetalResources?

    /// ヘッドレス（ウィンドウ無し・Syphon 出力のみ）で起動しているかどうか。
    /// 環境変数 `METAPHOR_VIEWER=1` で有効化され、metaphor-cli のライブビューアが
    /// 子プロセスとしてスケッチを実行する際に利用します。
    private var isHeadless = false

    // MARK: - Entry Point

    /// 指定されたスケッチ型でアプリケーションを起動します。
    ///
    /// `NSApplication` を作成し、スケッチをインスタンス化して
    /// ランループを開始します。
    ///
    /// - Parameter sketchType: インスタンス化して実行する具象 `Sketch` 型。
    static func run(sketchType: any Sketch.Type) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let runner = SketchRunner()
        app.delegate = runner

        // スケッチインスタンスを作成
        let sketch = sketchType.init()
        runner.sketchRef = sketch

        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let sketch = sketchRef else { return }
        setup(sketch: sketch)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // ヘッドレスモードではウィンドウが無いため、ウィンドウ起因の終了はしない。
        if isHeadless { return false }
        // プライマリウィンドウが閉じられた場合のみ終了
        return !(window?.isVisible ?? false)
    }

    // MARK: - Setup

    /// スケッチを構成して実行します。
    ///
    /// 通常はウィンドウ + `MTKView` を構築しますが、環境変数 `METAPHOR_VIEWER=1`
    /// が設定されている場合はヘッドレス（ウィンドウ無し・Syphon 出力のみ）で起動します。
    /// ヘッドレスモードは metaphor-cli のライブビューアが子プロセスとして利用します。
    ///
    /// レンダラー・キャンバス・描画コールバックの構成は両モードで共通で、
    /// フレーム出力先（ウィンドウへのブリット or Syphon publish）とレンダーループ駆動
    /// （ディスプレイリンク/タイマー）のみがモードごとに異なります。
    ///
    /// - Parameter sketch: 設定がセットアップを駆動するスケッチインスタンス。
    private func setup(sketch: any Sketch) {
        let config = sketch.config
        isHeadless = ProcessInfo.processInfo.environment["METAPHOR_VIEWER"] == "1"

        // どの metaphor 版で動いているかを起動時に1行表示（後からログを見たときの
        // バージョン取り違え防止）。ヘッドレス時はモードも添える。
        let mode = isHeadless ? " (headless)" : ""
        FileHandle.standardError.write(
            "[metaphor] \(Metaphor.version)\(mode)\n".data(using: .utf8)!
        )

        // レンダラー・キャンバス・コンテキストを初期化（ウィンドウ非依存）。
        guard setupCore(sketch: sketch, config: config),
              let renderer = self.renderer,
              let context = self.context else {
            return
        }

        // スケッチ実行中は App Nap を抑止（既定）。ウィンドウが背面・オクルージョン状態に
        // なるとタイマー間引き + QoS 降格で描画内容と無関係に fps が低下するため（#266、
        // 実測で最大 1/6）、レンダーループモードによらずプロセススコープの assertion を
        // 張る。解放は applicationWillTerminate（SketchWindow の timer モードは Syphon
        // 出力用途のため、このオプトアウトと独立に自前の assertion を維持する）。
        if Self.resolvePreventAppNap(config: config, env: ProcessInfo.processInfo.environment) {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "metaphor sketch is running"
            )
        } else {
            metaphorDiagnostic(
                "App Nap prevention disabled (preventAppNap=false or METAPHOR_ALLOW_APP_NAP=1)"
            )
        }

        // レンダーループとフレーム出力先を構成（モード別）。
        if isHeadless {
            configureHeadlessLoop(config: config)
        } else {
            configureWindowedLoop(config: config)
        }

        // 入力コールバックをスケッチのイベントメソッドに接続。
        // ヘッドレスでは下の InputInjectionPlugin が stdin からイベントを注入する。
        connectInput(sketch: sketch, input: renderer.input, renderer: renderer)

        // config からプラグインを登録（setup() の前に利用可能にするため）
        for factory in config.plugins {
            let plugin = factory.create()
            renderer.addPlugin(plugin, sketch: sketch)
        }

        // METAPHOR_PROBE=1 が設定されていれば AI 向け観測プラグインを自動登録
        if ProcessInfo.processInfo.environment["METAPHOR_PROBE"] == "1",
           renderer.plugin(id: MetaphorProbePlugin.id) == nil {
            renderer.addPlugin(MetaphorProbePlugin(), sketch: sketch)
        }

        // ヘッドレス（ライブビューア）モードでは stdin 入力注入プラグインを自動登録。
        // 親プロセス（metaphor-cli）が JSON Lines でイベントを送る。
        if isHeadless,
           renderer.plugin(id: InputInjectionPlugin.id) == nil {
            renderer.addPlugin(InputInjectionPlugin(), sketch: sketch)
        }

        // setup() 中に noLoop ハンドラを一時的に抑制し、
        // onDraw が構成される前の早期一時停止を防止。
        context.onNoLoop = nil

        // setup()
        sketch.setup()

        // noLoop ハンドラを復元
        context.onNoLoop = { [weak self] in
            self?.handleNoLoop()
        }

        // コンピュートフェーズ + 描画ループのコールバックを構成
        configureRenderCallbacks(sketch: sketch, context: context, renderer: renderer)

        // レンダラーがフレーム生成を開始したことをプラグインに通知。
        // noLoop スケッチは start*Loop 内で最初のフレームを同期描画するため、
        // 描画前に onStart を発火させ、リソース確保の機会を保証する。
        renderer.notifyPluginsStart()

        // レンダーループを開始（モード別）
        if isHeadless {
            startHeadlessLoop(context: context, renderer: renderer)
        } else {
            startWindowedLoop(config: config, context: context, renderer: renderer)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // レンダータイマー停止 + App Nap 抑制解除（SketchWindow.stopRenderTimer と対称）。
        // cancel 後に resume するのは、suspend されたまま（noLoop 中など）の
        // DispatchSource は解放時にクラッシュするため — cancel 済みなので resume で
        // イベントハンドラが再発火することはなく、suspend カウントだけが 0 に戻る。
        if let renderTimer {
            renderTimer.cancel()
            resumeRenderTimerIfNeeded(renderTimer)
            self.renderTimer = nil
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        // レンダーループ停止 → プラグイン解放（onStop → onDetach）。
        // SyphonPlugin はここで Syphon サーバーを停止する。
        renderer?.shutdown()
        // Sketch → SketchContext ストレージからエントリを削除し、
        // context（renderer 一式）への強参照を解放する（teardown 経路）
        sketchRef?._context = nil
    }

    /// レンダラー・キャンバス・コンテキストとその制御コールバックを初期化します。
    ///
    /// ウィンドウや `MTKView` には依存せず、ウィンドウモードとヘッドレスモードで共通です。
    /// 成功時に `self.renderer` / `self.canvas` / `self.canvas3D` / `self.context` を設定します。
    ///
    /// - Returns: 初期化に成功したら `true`、失敗（エラーアラート表示）なら `false`。
    private func setupCore(sketch: any Sketch, config: SketchConfig) -> Bool {
        // 共有リソース + レンダラー + キャンバスを初期化
        let shared: SharedMetalResources
        let renderer: MetaphorRenderer
        let canvas: Canvas2D
        let canvas3D: Canvas3D
        do {
            shared = try SharedMetalResources()
            renderer = try MetaphorRenderer(
                sharedResources: shared,
                width: config.width,
                height: config.height
            )
            canvas = try Canvas2D(renderer: renderer)
            canvas3D = try Canvas3D(renderer: renderer)
        } catch {
            showErrorAlert(error: error)
            return false
        }
        self.sharedResources = shared
        self.renderer = renderer

        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        self.canvas = canvas
        self.canvas3D = canvas3D

        // SketchContext
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        self.context = context
        context.isPrimary = true
        context._sharedResources = shared
        assert(sketch._context == nil, "Sketch context already set — this may indicate duplicate setup")
        sketch._context = context

        // createCanvas コールバック（setup() 内でのリサイズを許可）
        context.onCreateCanvas = { [weak self] width, height in
            self?.handleCreateCanvas(width: width, height: height, config: config)
        }

        // アニメーション制御コールバック
        context.onLoop = { [weak self] in
            self?.handleLoop()
        }
        context.onNoLoop = { [weak self] in
            self?.handleNoLoop()
        }
        context.onRedraw = { [weak self] in
            self?.handleRedraw()
        }
        context.onFrameRate = { [weak self] fps in
            self?.handleFrameRate(fps)
        }

        return true
    }

    /// ウィンドウ + `MTKView` を構築し、レンダーループモードを構成します。
    private func configureWindowedLoop(config: SketchConfig) {
        guard let renderer else { return }

        // ウィンドウサイズ
        let windowWidth = CGFloat(Float(config.width) * config.windowScale)
        let windowHeight = CGFloat(Float(config.height) * config.windowScale)

        let windowRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = config.title
        window.contentAspectRatio = NSSize(width: config.width, height: config.height)
        window.center()
        self.window = window

        // MTKView
        let mtkView = MetaphorMTKView()
        mtkView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoresizingMask = [.width, .height]
        renderer.configure(view: mtkView)
        mtkView.enableFileDrop()
        window.contentView = mtkView
        self.mtkView = mtkView

        // Syphon 実効名の解決（環境変数 > config.syphonName > (config.syphon ? title : nil)）。
        // ウィンドウ表示でも MadMapper 等へ publish できるよう、env / syphon フラグを尊重する。
        let effectiveSyphonName = resolveSyphonName(config: config)

        // FPS: 環境変数 `METAPHOR_FPS` で上書き可能（ウィンドウモードでも尊重）。
        let fps = resolveFPS(config: config)

        // レンダーループモードの決定。
        // Syphon を publish するが renderLoopMode が displayLink のままの場合、
        // Syphon 互換性のため自動的にタイマーモードに切り替え。
        let loopMode: RenderLoopMode
        if effectiveSyphonName != nil && config.renderLoopMode == .displayLink {
            loopMode = .timer(fps: fps)
        } else {
            loopMode = config.renderLoopMode
        }

        // 出力（オプトイン: config.syphon / config.syphonName / 環境変数のいずれか）。
        // 具体的な出力実装（Syphon 等）は MetaphorOutputRegistry 経由で間接的に起動する
        // （Core は Syphon を名指ししない）。
        if let effectiveSyphonName {
            startOutput(renderer: renderer, name: effectiveSyphonName)
        }

        // レンダーループの構成。
        // 両モードとも、onDraw のセットアップ前に CVDisplayLink が発火する
        // 競合を避けるため、ディスプレイリンクを一時停止した状態で開始。
        // セットアップ完了後にディスプレイリンクを再開（または明示的に
        // 1フレームを描画）— startWindowedLoop を参照。
        switch loopMode {
        case .displayLink:
            mtkView.preferredFramesPerSecond = fps
            mtkView.isPaused = true

        case .timer(let timerFPS):
            // タイマー駆動のレンダーループを開始（ディスプレイリンクから分離）
            startTimerLoop(fps: timerFPS)

            // MTKView: ディスプレイリンクはプレビューとしてのみ使用（スロットリングは許容）
            mtkView.preferredFramesPerSecond = timerFPS
            mtkView.isPaused = false
        }
    }

    /// Syphon サーバーの実効名を解決します（ウィンドウ表示モード用）。
    ///
    /// 優先順位: 環境変数 `METAPHOR_SYPHON_NAME` > ``SketchConfig/syphonName`` >
    /// （``SketchConfig/syphon`` が `true` なら ``SketchConfig/title``）。いずれも無ければ
    /// `nil`（= Syphon 無効）。空文字の環境変数は未設定として扱います。
    private func resolveSyphonName(config: SketchConfig) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let name = env["METAPHOR_SYPHON_NAME"], !name.isEmpty { return name }
        if let name = config.syphonName { return name }
        if config.syphon { return config.title }
        return nil
    }

    /// App Nap 抑止の assertion を張るべきかを解決します。
    ///
    /// 優先順位: 環境変数 `METAPHOR_ALLOW_APP_NAP=1`（= App Nap を許可、抑止しない）>
    /// ``SketchConfig/preventAppNap``。ビルド済みスケッチを再コンパイルせず省電力側に
    /// 倒すためのスイッチです。
    ///
    /// - Parameters:
    ///   - config: スケッチ設定。
    ///   - env: 参照する環境変数（テストから注入可能）。
    /// - Returns: assertion を張るべきなら `true`。
    nonisolated static func resolvePreventAppNap(
        config: SketchConfig, env: [String: String]
    ) -> Bool {
        if env["METAPHOR_ALLOW_APP_NAP"] == "1" { return false }
        return config.preventAppNap
    }

    /// レンダーループの実効 FPS を解決します（ウィンドウ/ヘッドレス共通）。
    ///
    /// 優先順位: 環境変数 `METAPHOR_FPS` > ``SketchConfig/fps``。これにより
    /// metaphor-cli の `--fps` がヘッドレス（ライブビューア）だけでなく、ウィンドウ
    /// モード（`metaphor run` / `watch --no-viewer`）でも一様に効きます。
    /// 解析できない値（非数値・0 以下）は無視して `config.fps` にフォールバックします。
    private func resolveFPS(config: SketchConfig) -> Int {
        guard let raw = ProcessInfo.processInfo.environment["METAPHOR_FPS"],
              let fps = Int(raw), fps > 0 else {
            return config.fps
        }
        return fps
    }

    /// 解決済みの出力名で、登録済みファクトリ（例: `MetaphorSyphon`）から出力プラグインを
    /// 起動します。
    ///
    /// 出力 target が未リンク（＝ ``MetaphorOutputRegistry/factory`` 未登録）の場合は
    /// 警告を出して何もしません。これにより `MetaphorCore` 単体（Syphon 抜き）でも安全に
    /// 動作します。`import metaphor`（アンブレラ）経由では `MetaphorSyphon` がリンクされ、
    /// ファクトリがロード時に自動登録されるため、従来どおり透過的に Syphon が起動します。
    private func startOutput(renderer: MetaphorRenderer, name: String) {
        guard let plugin = MetaphorOutputRegistry.makeOutput(name: name) else {
            // 出力先が無いままレンダーループだけ回り続けると原因の手掛かりが
            // 一切出ないため明示する。ヘッドレスモードは「ウィンドウ無し・
            // 出力のみ」なので error 級（Release でも stderr に出す）
            let message = "output '\(name)' was requested but no output module is linked. "
                + "Import the umbrella 'metaphor' (or 'MetaphorSyphon'), or call MetaphorSyphon.enable()."
            if isHeadless {
                FileHandle.standardError.write(
                    "[metaphor] ERROR: \(message)\n".data(using: .utf8)!
                )
            } else {
                metaphorWarning(message)
            }
            return
        }
        renderer.addPlugin(plugin)
    }

    /// ヘッドレス（ウィンドウ無し）モードのレンダーループと Syphon 出力を構成します。
    ///
    /// ウィンドウ/`MTKView`/ブリットパスを生成せず、常にタイマー駆動で `renderFrame()` を
    /// 回し、結果を Syphon 経由で publish します。Syphon サーバー名と FPS は環境変数で
    /// 上書きできます（`METAPHOR_SYPHON_NAME` / `METAPHOR_FPS`）。
    private func configureHeadlessLoop(config: SketchConfig) {
        guard let renderer else { return }

        // Dock / メニューバーに出さない（バックグラウンドのレンダリングプロセス）。
        NSApp.setActivationPolicy(.accessory)

        let env = ProcessInfo.processInfo.environment

        // 出力サーバー名: 環境変数 > config.syphonName > タイトル の優先順。
        let syphonName = env["METAPHOR_SYPHON_NAME"] ?? config.syphonName ?? config.title
        startOutput(renderer: renderer, name: syphonName)

        // FPS: 環境変数 `METAPHOR_FPS` で上書き可能（ウィンドウモードと共通）。
        let fps = resolveFPS(config: config)

        // ヘッドレスは常にタイマー駆動（ディスプレイリンクは MTKView 前提のため）。
        startTimerLoop(fps: fps)
    }

    /// `DispatchSourceTimer` ベースのレンダーループを開始します。
    ///
    /// ディスプレイリンクから独立して `renderFrame()` を駆動します。ウィンドウモードの
    /// タイマー指定時とヘッドレスモードの両方で使用します。
    private func startTimerLoop(fps: Int) {
        guard let renderer else { return }

        // レンダリングをディスプレイリンクから分離
        renderer.useExternalRenderLoop = true

        // DispatchSourceTimer: ディスプレイリンクとは独立して renderFrame() を駆動
        let interval = 1.0 / Double(max(fps, 1))
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak renderer] in
            dispatchPrecondition(condition: .onQueue(.main))
            MainActor.assumeIsolated {
                renderer?.renderFrame()
            }
        }
        timer.resume()
        isRenderTimerSuspended = false
        renderTimer = timer
    }

    /// コンピュートフェーズと描画ループのレンダラーコールバックを構成します（両モード共通）。
    private func configureRenderCallbacks(
        sketch: any Sketch, context: SketchContext, renderer: MetaphorRenderer
    ) {
        // コマンド記録 opt-in（#71）: 影オフスケッチでも記録→再生経路で呼び出し順を保持する。
        // 既定は無効（影オフは従来の即時経路＝回帰ゼロ）。
        if ProcessInfo.processInfo.environment["METAPHOR_COMMAND_RECORD"] == "1" {
            context.canvas3D.commandRecordEnabled = true
        }

        // onCompute と onDraw で共有する直前フレーム時刻（onDraw が更新）。
        var prevTime: Float = 0

        renderer.onCompute = { [weak context, weak sketch] commandBuffer, time in
            guard let context, let sketch else { return }
            let t = Float(time)
            let dt = t - prevTime
            context.beginCompute(commandBuffer: commandBuffer, time: t, deltaTime: dt)
            sketch.compute()
            context.endCompute()
        }

        renderer.onDraw = { [weak context, weak sketch] encoder, time in
            guard let context, let sketch else { return }
            let t = Float(time)
            let dt = t - prevTime
            prevTime = t
            context.beginFrame(encoder: encoder, time: t, deltaTime: dt, preciseTime: time)
            sketch.draw()
            context.endFrame()
        }

        renderer.onAfterDraw = { [weak context] commandBuffer in
            guard let context else { return }
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }

        // 記録→shadow→再生の経路: 影オン（#70）またはコマンド記録 opt-in（#71）で使う。
        renderer.shadowDeferActive = { [weak context] in
            context?.canvas3D.shouldRecordMainPass ?? false
        }
        renderer.onRecordFrame = { [weak context, weak sketch] time in
            guard let context, let sketch else { return }
            let t = Float(time)
            let dt = t - prevTime
            prevTime = t
            context.beginRecordingFrame(time: t, deltaTime: dt)
            sketch.draw()
            context.endRecordingFrame()
        }
        renderer.onReplayMain = { [weak context] encoder, time in
            guard let context else { return }
            context.replayDeferredMain(encoder: encoder, time: Float(time))
        }
    }

    /// ウィンドウを表示し、ウィンドウモードのレンダーループを開始します。
    private func startWindowedLoop(
        config: SketchConfig, context: SketchContext, renderer: MetaphorRenderer
    ) {
        guard let window, let mtkView else { return }

        // レンダーループ開始前にウィンドウを表示し、drawable が
        // 適切なサイズに設定されるようにする（例: Retina の contentsScale 解決）。
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(mtkView)
        NSApp.activate()

        // 設定されている場合はフルスクリーンに移行
        if config.fullScreen {
            window.toggleFullScreen(nil)
        }

        // レンダーループを開始。ディスプレイリンクはセットアップ中一時停止されており、
        // onDraw / onCompute が完全に構成された後にのみ最初の draw(in:) が
        // 発火することを保証。
        if context.isLooping {
            // ループするスケッチ: ディスプレイリンクを再開。
            // （タイマーモードは上で既に実行中。）
            if renderTimer == nil {
                mtkView.isPaused = false
            }
        } else {
            // noLoop(): 同期的に正確に1フレームをレンダリング。
            // isPaused が true のままなのでそれ以上のフレームは生成されず、
            // isPaused が有効になる前に CVDisplayLink が2回目を発火する
            // 競合を排除。
            if let renderTimer {
                suspendRenderTimerIfNeeded(renderTimer)
            }
            // オフスクリーンを1回だけレンダリング。clearColorApplied が false の
            // ため background() は全画面クワッドで背景を塗り、この時点でオフスクリーン
            // テクスチャは正しい背景色を持つ。
            renderer.renderFrame()
            // useExternalRenderLoop = true にして draw(in:) を「再レンダリングせず
            // ブリットのみ」へ切り替え、上記オフスクリーンを画面へ転送する。これにより
            // 2 回目の draw() による frameCount=2 を回避し、初回 snapshot を決定論化（#70）。
            let wasExternal = renderer.useExternalRenderLoop
            renderer.useExternalRenderLoop = true
            mtkView.draw()
            renderer.useExternalRenderLoop = wasExternal
        }
    }

    /// ヘッドレスモードのレンダーループを開始します。
    ///
    /// タイマーは ``configureHeadlessLoop(config:)`` で既に起動済みです。`noLoop()` の
    /// スケッチではタイマーを止め、1フレームだけレンダリングして Syphon に publish します。
    /// `frameCount` を 1 に保ち初回 snapshot を決定論化します（#70、ウィンドウモードと同じ意図）。
    private func startHeadlessLoop(context: SketchContext, renderer: MetaphorRenderer) {
        guard !context.isLooping else { return }

        // noLoop(): タイマーを止めて静止フレームをレンダリング。
        if let renderTimer {
            suspendRenderTimerIfNeeded(renderTimer)
        }
        // 1フレームだけレンダリングして frameCount を 1 に保つ（#70）。
        // clearColorApplied が false のため background() は全画面クワッドで背景を
        // 塗るので、この単一パスでオフスクリーン/Syphon 出力は正しい背景色を持つ。
        renderer.renderFrame()
    }

    // MARK: - Animation Control

    /// レンダーループを再開します。
    private func handleLoop() {
        if let renderTimer {
            resumeRenderTimerIfNeeded(renderTimer)
        } else {
            mtkView?.isPaused = false
        }
        renderer?.notifyPluginsStart()
    }

    /// レンダーループを一時停止します。
    private func handleNoLoop() {
        if let renderTimer {
            suspendRenderTimerIfNeeded(renderTimer)
        } else {
            mtkView?.isPaused = true
        }
        renderer?.notifyPluginsStop()
    }

    /// 単一フレームの再描画をトリガーします。
    ///
    /// ``MTKView/draw()`` を同期的に呼び出し、デリゲートの
    /// ``MTKViewDelegate/draw(in:)`` を正確に1回実行します。
    /// ``MTKView/isPaused`` のトグルによるタイミングの不確実性を回避します。
    private func handleRedraw() {
        if renderTimer != nil {
            // タイマーモード: まずオフスクリーンをレンダリング（draw(in:) はブリットのみ）
            renderer?.renderFrame()
        }
        // MTKView.draw() は draw(in:) を同期的にトリガー。
        // ディスプレイリンクモード: renderFrame() + ブリットを1回の呼び出しで実行。
        // タイマーモード: 直前にレンダリングしたオフスクリーンテクスチャをブリット。
        mtkView?.draw()
    }

    /// レンダーループのフレームレートを更新します。
    ///
    /// - Parameter fps: 目標フレーム毎秒。
    private func handleFrameRate(_ fps: Int) {
        if let renderTimer {
            // タイマーモード: タイマーをリスケジュール
            let interval = 1.0 / Double(max(fps, 1))
            renderTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        } else {
            // ディスプレイリンクモード: MTKView の優先フレームレートを更新
            mtkView?.preferredFramesPerSecond = fps
        }
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

    /// テクスチャ、キャンバス、ウィンドウを新しいキャンバスサイズに合わせて再構築します。
    ///
    /// - Parameters:
    ///   - width: 新しいキャンバスの幅（ピクセル単位）。
    ///   - height: 新しいキャンバスの高さ（ピクセル単位）。
    ///   - config: ウィンドウスケール計算に使用するスケッチ設定。
    private func handleCreateCanvas(width: Int, height: Int, config: SketchConfig) {
        guard let renderer, let context else { return }

        // テクスチャをリサイズ
        renderer.resizeCanvas(width: width, height: height)

        // Canvas2D / Canvas3D を再構築
        guard let newCanvas = try? Canvas2D(renderer: renderer),
              let newCanvas3D = try? Canvas3D(renderer: renderer) else {
            return
        }
        newCanvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        self.canvas = newCanvas
        self.canvas3D = newCanvas3D
        context.rebuildCanvas(canvas: newCanvas, canvas3D: newCanvas3D)

        // ウィンドウサイズを更新
        let windowWidth = CGFloat(Float(width) * config.windowScale)
        let windowHeight = CGFloat(Float(height) * config.windowScale)
        window?.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window?.contentAspectRatio = NSSize(width: width, height: height)
        window?.center()
    }

    /// エラーアラートを表示しアプリケーションを終了します。
    ///
    /// - Parameter error: ユーザーに提示する初期化エラー。
    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "metaphor initialization failed"
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    /// 入力マネージャのコールバックをスケッチのイベントメソッドとプラグイン転送に接続します。
    ///
    /// - Parameters:
    ///   - sketch: 入力イベントを受け取るスケッチインスタンス。
    ///   - input: 生の入力コールバックを提供する入力マネージャ。
    ///   - renderer: プラグインも入力イベントを受け取るレンダラー。
    private func connectInput(sketch: any Sketch, input: InputManager, renderer: MetaphorRenderer) {
        input.onMousePressed = { [weak sketch, weak renderer] x, y, button in
            sketch?.mousePressed()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .pressed)
        }
        input.onMouseReleased = { [weak sketch, weak renderer] x, y, button in
            sketch?.mouseReleased()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .released)
        }
        input.onMouseMoved = { [weak sketch, weak renderer] x, y in
            sketch?.mouseMoved()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: 0, type: .moved)
        }
        input.onMouseDragged = { [weak sketch, weak renderer] x, y in
            sketch?.mouseDragged()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: 0, type: .dragged)
        }
        input.onMouseScrolled = { [weak sketch, weak renderer] dx, dy in
            sketch?.mouseScrolled()
            let mx = renderer?.input.mouseX ?? 0
            let my = renderer?.input.mouseY ?? 0
            renderer?.notifyPluginsMouseEvent(x: mx, y: my, button: 0, type: .scrolled)
        }
        input.onMouseClicked = { [weak sketch, weak renderer] x, y, button in
            sketch?.mouseClicked()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .clicked)
        }
        input.onKeyDown = { [weak sketch, weak renderer] keyCode, characters in
            sketch?.keyPressed()
            renderer?.notifyPluginsKeyEvent(key: characters?.first, keyCode: keyCode, type: .pressed)
        }
        input.onKeyUp = { [weak sketch, weak renderer] keyCode in
            sketch?.keyReleased()
            renderer?.notifyPluginsKeyEvent(key: nil, keyCode: keyCode, type: .released)
        }
    }
}
