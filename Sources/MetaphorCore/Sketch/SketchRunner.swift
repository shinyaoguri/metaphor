import AppKit
import MetalKit
import QuartzCore

/// スケッチのライフサイクルを管理します。
///
/// `NSApplicationDelegate` として動作し、プログラム的にウィンドウ、
/// `MTKView`、レンダラーを構築します。ユーザーがこのクラスを
/// 直接操作することはありません。
@MainActor
final class SketchRunner: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    // internal: テストから直接 handleFrameRate(_:) を検証できるようにする(#358)
    var mtkView: MetaphorMTKView?
    var renderer: MetaphorRenderer?
    private var canvas: Canvas2D?
    private var canvas3D: Canvas3D?
    private var context: SketchContext?
    private var sketchRef: (any Sketch)?
    private var renderTimer: DispatchSourceTimer?
    private var isRenderTimerSuspended = false
    // 描画コールバックが共有する直前フレーム時刻。ループを止めている間も時計は進むため、
    // 再開時に起点を寄せ直せるよう runner 側で保持する(#793)。
    // internal: テストから handleLoop() の効果を検証できるようにする。
    let frameClock = FrameClock()
    private var activity: NSObjectProtocol?
    private var sharedResources: SharedMetalResources?

    /// ヘッドレス（ウィンドウ無し・出力プラグインのみ）で起動しているかどうか。
    /// 環境変数 `METAPHOR_VIEWER=1` で有効化され、metaphor-cli のライブビューアが
    /// 子プロセスとしてスケッチを実行する際に利用します。
    private var isHeadless = false

    /// ヘッドレス実行中であることを示すメニューバーの状態項目（出さない設定なら `nil`）。
    private var headlessStatusItem: HeadlessStatusItem?

    /// メニューを開いている間だけ最新フレームを取り出すプラグイン（出さない設定なら `nil`）。
    private var headlessPreviewTap: HeadlessPreviewTap?

    /// 状態項目に出す経過時間の起点（`CACurrentMediaTime()`）。
    private var headlessIndicatorStart: Double = 0

    /// 状態項目に出す出力先プラグインの識別子（ヘッドレス構成時に確定する）。
    private var headlessOutputPluginIDs: [String] = []

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

        // SIGTERM / SIGINT を通常終了と同じ後始末経路へ合流させる（#715）。
        // source は解放するとハンドラが外れるため、プロセス寿命まで保持する。
        retainedSignalSources = installTerminationSignalHandlers()

        app.run()
    }

    /// 終了シグナル（`SIGINT` / `SIGTERM`）を受けたら `NSApp.terminate(_:)` を呼び、
    /// 通常終了と同じ後始末（``applicationWillTerminate(_:)``）を通してから終了させます。
    ///
    /// 既定のシグナル動作はプロセスを即座に終了させるため、`applicationWillTerminate` が
    /// 走らず ``MetaphorRenderer/shutdown()`` → プラグインの `onDetach()` に到達しません。
    /// 結果として Syphon サーバーの retire 通知が送出されず、`SyphonServerDirectory` を
    /// 保持し続けているクライアント（ライブビューア・MadMapper 等）からは死んだサーバーが
    /// 生きているように見え続けます。`metaphor watch` はリロードのたびに子スケッチを
    /// `SIGTERM` で止めるため、リロードのたびにゾンビが 1 つ増えていました（#715）。
    ///
    /// シグナルハンドラ内で呼べる関数は限られる（async-signal-safe）ため、
    /// `signal(sig, SIG_IGN)` でデフォルト動作を無効にしたうえで `DispatchSource` で受け、
    /// 実際の後始末は通常のキューで実行します（metaphor-cli 側も同型）。
    ///
    /// - Parameters:
    ///   - env: 参照する環境変数（テストから注入可能）。
    ///   - onTerminate: シグナル受信時に実行する処理。既定はメインスレッドでの
    ///     `NSApp.terminate(nil)`（テストから差し替え可能）。
    /// - Returns: 設置した signal source。**呼び出し側が保持し続ける必要があります**
    ///   （解放するとハンドラが外れる）。オプトアウト時は空配列。
    nonisolated static func installTerminationSignalHandlers(
        env: [String: String] = ProcessInfo.processInfo.environment,
        onTerminate: (@Sendable () -> Void)? = nil
    ) -> [any DispatchSourceSignal] {
        guard resolveInstallSignalHandlers(env: env) else { return [] }

        let terminate = onTerminate ?? {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }

        return [SIGINT, SIGTERM].map { sig in
            // デフォルト動作（即時終了）を無効にしないと DispatchSource へ届く前に殺される。
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler(handler: terminate)
            source.resume()
            return source
        }
    }

    /// 終了シグナルのハンドラを設置するか（既定は設置する）。
    ///
    /// 環境変数 `METAPHOR_SIGNAL_HANDLERS=0` でオプトアウトできます。スケッチを組み込んだ
    /// ホスト側が独自にシグナルを扱いたい場合の逃げ道で、`0` 以外の値は無視します。
    nonisolated static func resolveInstallSignalHandlers(env: [String: String]) -> Bool {
        env["METAPHOR_SIGNAL_HANDLERS"] != "0"
    }

    /// 設置した signal source の保持先（プロセス寿命）。
    ///
    /// `run(sketchType:)` から 1 回だけ書き込み、以降は読み書きしないため
    /// `nonisolated(unsafe)` とします。
    private nonisolated(unsafe) static var retainedSignalSources: [any DispatchSourceSignal] = []

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
    /// が設定されている場合はヘッドレス（ウィンドウ無し・出力プラグインのみ）で起動します。
    /// ヘッドレスモードは metaphor-cli のライブビューアが子プロセスとして利用します。
    ///
    /// レンダラー・キャンバス・描画コールバックの構成は両モードで共通で、
    /// フレーム出力先（ウィンドウへのブリット or 出力プラグインの publish）とレンダーループ駆動
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

        // Core 内蔵の出力 provider（METAPHOR_VIEWER_SOCKET → ViewerOutputPlugin。契約点 5）を
        // 走査の前に登録する（冪等）。Syphon 等の外部モジュールはロード時に自分で登録している。
        ViewerOutputProvider.register()

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

        // `@Param` が 1 つでも宣言されていれば Parameter Store を自動有効化
        // （素の `swift run` でも永続化が効く = cli 不要の単独価値）。
        // オプトアウトは METAPHOR_PARAMS=0。Mirror 走査はここ 1 回だけで、
        // フレームループには現れない。
        if ParameterPlugin.shouldAutoRegister(
            sketch: sketch, env: ProcessInfo.processInfo.environment
        ), renderer.plugin(id: ParameterPlugin.id) == nil {
            renderer.addPlugin(ParameterPlugin(), sketch: sketch)
        }

        // リロードをまたぐ状態保存（契約点 8）。既定で有効なのはヘッドレス
        // （`metaphor watch` の子プロセス = save-request を書く相手が居る経路）だけ。
        // METAPHOR_STATE=1 で明示有効・=0 でオプトアウト。
        if StatePlugin.shouldAutoRegister(env: ProcessInfo.processInfo.environment),
           renderer.plugin(id: StatePlugin.id) == nil {
            renderer.addPlugin(StatePlugin(), sketch: sketch)
        }

        // ヘッドレス（ライブビューア）モードでは stdin 入力注入プラグインを自動登録。
        // 親プロセス（metaphor-cli）が JSON Lines でイベントを送る。
        if isHeadless,
           renderer.plugin(id: InputInjectionPlugin.id) == nil {
            renderer.addPlugin(InputInjectionPlugin(), sketch: sketch)
        }

        // シェーダファイルの自動ホットリロード（#648）。setup() の前に決める：
        // ファイル由来のシェーダを読むのは大抵 setup() の中で、そこで監視登録が走る。
        context.shaderHotReloadEnabled = Self.resolveShaderHotReload(
            config: config, env: ProcessInfo.processInfo.environment
        )

        // setup() 中に noLoop ハンドラを一時的に抑制し、
        // onDraw が構成される前の早期一時停止を防止。
        context.onNoLoop = nil

        // setup()
        sketch.setup()

        // noLoop ハンドラを復元
        context.onNoLoop = { [weak self] in
            self?.handleNoLoop()
        }

        // 直前のプロセスが保存した状態を復元（`metaphor watch` のリロード。契約点 8）。
        // setup() の後・描画コールバック構成の前に置く: スケッチが setup() で確保した器の
        // 上に値を載せ、時計オフセットを prevTime の初期化より先に確定させるため。
        Self.applyRestoredState(
            sketch: sketch, context: context, renderer: renderer, config: config
        )

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
        // ヘッドレスの状態項目をメニューバーから外す（残すと終了後もアイコンが居座る）。
        headlessStatusItem?.remove()
        headlessStatusItem = nil
        // シェーダ監視の DispatchSource を止める（#648）。
        context?.stopShaderHotReload()
        // レンダーループ停止 → プラグイン解放（onStop → onDetach）。
        // 出力プラグイン（viewer / Syphon 等）はここで接続やサーバーを閉じる。
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
                height: config.height,
                sampleCount: config.msaa
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

        // 生成は SketchWindowFactory へ集約（isReleasedWhenClosed = false を含む。#835）。
        // プライマリは applicationShouldTerminateAfterLastWindowClosed が閉じたあとに
        // `window?.isVisible` を読むため、AppKit に解放されると解放済み参照を触る。
        let window = SketchWindowFactory.makeWindow(
            contentSize: NSSize(width: windowWidth, height: windowHeight),
            title: config.title,
            aspectRatio: NSSize(width: config.width, height: config.height)
        )
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

        let env = ProcessInfo.processInfo.environment

        // FPS: 環境変数 `METAPHOR_FPS` で上書き可能（ウィンドウモードでも尊重）。
        let fps = Self.resolveFPS(config: config, env: env)
        renderer.targetFPS = fps

        // 出力（Syphon 等）は登録済み provider の走査で決まる（Core は出力実装を名指ししない）。
        // ウィンドウ表示でも MadMapper 等へ publish できるよう、provider には env / config を渡す。
        let outputs = MetaphorOutputProviders.makeOutputs(
            context: MetaphorOutputContext(scope: .primary(config), environment: env, isHeadless: false)
        )

        // レンダーループモードの決定。config.plugins と出力 provider が宣言した要件を
        // プラグイン生成より前に集計する（外部ループが要る出力があれば displayLink → timer）。
        let loopMode = Self.resolveLoopMode(
            config: config, fps: fps,
            requirements: Self.aggregateRequirements(config: config, outputs: outputs),
            isHeadless: false
        )

        attachOutputs(outputs, renderer: renderer, env: env)

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

    /// 実効レンダーループモードを解決します（純粋関数。``RenderLoopMode/resolve(requested:fps:requirements:isHeadless:)`` に委譲）。
    ///
    /// - Parameters:
    ///   - config: スケッチ設定（``SketchConfig/renderLoopMode`` が要求モード）。
    ///   - fps: 実効 FPS（`resolveFPS(config:env:)` の結果）。
    ///   - requirements: `aggregateRequirements(config:outputs:)` の結果。
    ///   - isHeadless: ヘッドレスかどうか。
    nonisolated static func resolveLoopMode(
        config: SketchConfig, fps: Int, requirements: PluginRequirements, isHeadless: Bool
    ) -> RenderLoopMode {
        RenderLoopMode.resolve(
            requested: config.renderLoopMode, fps: fps,
            requirements: requirements, isHeadless: isHeadless
        )
    }

    /// ``SketchConfig/plugins`` のファクトリと、出力 provider が返した出力の要件の和を取ります。
    nonisolated static func aggregateRequirements(
        config: SketchConfig, outputs: [MetaphorOutputProviders.ResolvedOutput]
    ) -> PluginRequirements {
        var requirements = PluginRequirements()
        for factory in config.plugins { requirements.formUnion(factory.requirements) }
        for output in outputs { requirements.formUnion(output.requirements) }
        return requirements
    }

    /// 出力が要求されているのに provider が 1 つも出力を返さなかったか（診断用）。
    ///
    /// 「要求」は明示の入口そのもの: 環境変数 `METAPHOR_SYPHON_NAME`（空文字は未設定扱い）。
    /// ヘッドレス起動（ウィンドウ無し）は**何も見えないプロセス**になり得るので、viewer socket
    /// （`METAPHOR_VIEWER_SOCKET`）も Probe（`METAPHOR_PROBE=1`）も出力も無いときだけ要求扱いにする
    /// （ADR-0014: ヘッドレスが Syphon を暗黙に立てることはもう無い。旧 `SketchConfig.syphon` /
    /// `syphonName` は v0.13.0 で削除）。
    nonisolated static func outputRequestedButMissing(
        env: [String: String], isHeadless: Bool,
        outputs: [MetaphorOutputProviders.ResolvedOutput]
    ) -> Bool {
        guard outputs.isEmpty else { return false }
        if let name = env["METAPHOR_SYPHON_NAME"], !name.isEmpty { return true }
        guard isHeadless else { return false }
        let hasViewerSocket = !(env["METAPHOR_VIEWER_SOCKET"] ?? "").isEmpty
        let hasProbe = env["METAPHOR_PROBE"] == "1"
        return !hasViewerSocket && !hasProbe
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

    /// ヘッドレス実行中であることをどこに出すかを解決します。
    ///
    /// 優先順位: 環境変数 `METAPHOR_HEADLESS_INDICATOR`（`menubar` / `dock` / `both` /
    /// `none`）> ``SketchConfig/headlessIndicator``。ビルド済みのスケッチを再コンパイル
    /// せずに切り替えるためのスイッチです（`METAPHOR_FPS` と同じ流儀）。解釈できない値は
    /// 警告を出して設定値へフォールバックします。
    ///
    /// - Parameters:
    ///   - config: スケッチ設定。
    ///   - env: 参照する環境変数（テストから注入可能）。
    /// - Returns: 実際に使う指標。
    nonisolated static func resolveHeadlessIndicator(
        config: SketchConfig, env: [String: String]
    ) -> HeadlessIndicator {
        guard let raw = env["METAPHOR_HEADLESS_INDICATOR"], !raw.isEmpty else {
            return config.headlessIndicator
        }
        guard let parsed = HeadlessIndicator.parse(raw) else {
            metaphorWarning(
                "METAPHOR_HEADLESS_INDICATOR=\(raw) is not one of menubar / dock / both / none; "
                + "using \(config.headlessIndicator.rawValue)"
            )
            return config.headlessIndicator
        }
        return parsed
    }

    /// シェーダファイルの自動ホットリロードを有効にするか（#648）。
    ///
    /// 環境変数 `METAPHOR_SHADER_HOT_RELOAD` が最優先（`1` で有効・`0` で無効）。
    /// 無ければ ``SketchConfig/shaderHotReload``（既定は DEBUG ビルドでのみ `true`）。
    nonisolated static func resolveShaderHotReload(
        config: SketchConfig, env: [String: String]
    ) -> Bool {
        switch env["METAPHOR_SHADER_HOT_RELOAD"] {
        case "1": return true
        case "0": return false
        default: return config.shaderHotReload
        }
    }

    /// レンダーループの実効 FPS を解決します（ウィンドウ/ヘッドレス共通）。
    ///
    /// 優先順位: 環境変数 `METAPHOR_FPS` > ``SketchConfig/fps``。これにより
    /// metaphor-cli の `--fps` がヘッドレス（ライブビューア）だけでなく、ウィンドウ
    /// モード（`metaphor run` / `watch --no-viewer`）でも一様に効きます。
    /// 解析できない値（非数値・0 以下）は無視して `config.fps` にフォールバックします。
    ///
    /// - Parameters:
    ///   - config: スケッチ設定。
    ///   - env: 参照する環境変数（テストから注入可能）。
    /// - Returns: 実効 FPS。
    nonisolated static func resolveFPS(config: SketchConfig, env: [String: String]) -> Int {
        guard let raw = env["METAPHOR_FPS"], let fps = Int(raw), fps > 0 else {
            return config.fps
        }
        return fps
    }

    /// 出力 provider が返した出力プラグインをレンダラーへ接続します（ウィンドウ / ヘッドレス共通）。
    ///
    /// 出力が要求されているのに provider が 1 つも無い（例えば Syphon を要求したのに
    /// `metaphor-syphon` パッケージが依存に入っていない）場合は警告を出して何もしません。
    /// metaphor-syphon を `Package.swift` に足すとロード時に provider が自動登録され、
    /// 出力 provider が返したプラグイン（`plugins: [.syphon(name:)]` や `METAPHOR_SYPHON_NAME` による
    /// metaphor-syphon の出力など）を renderer に取り付けます。
    private func attachOutputs(
        _ outputs: [MetaphorOutputProviders.ResolvedOutput],
        renderer: MetaphorRenderer, env: [String: String]
    ) {
        for output in outputs {
            renderer.addPlugin(output.plugin)
        }
        if Self.outputRequestedButMissing(env: env, isHeadless: isHeadless, outputs: outputs) {
            // 出力先が無いままレンダーループだけ回り続けると原因の手掛かりが
            // 一切出ないため明示する。ヘッドレスモードは「ウィンドウ無し・
            // 出力のみ」なので error 級（Release でも stderr に出す）
            let message = isHeadless && (env["METAPHOR_SYPHON_NAME"] ?? "").isEmpty
                ? "headless (METAPHOR_VIEWER=1) but nothing will observe the frames: set METAPHOR_VIEWER_SOCKET "
                    + "(metaphor watch --viewer), METAPHOR_PROBE=1, or request an output (METAPHOR_SYPHON_NAME with metaphor-syphon)."
                : "an output (METAPHOR_SYPHON_NAME) was requested but no output module is linked. "
                    + "Add the 'metaphor-syphon' package to Package.swift and pass plugins: [.syphon(name:)] "
                    + "(https://github.com/shinyaoguri/metaphor-syphon)."
            if isHeadless {
                FileHandle.standardError.write(
                    "[metaphor] ERROR: \(message)\n".data(using: .utf8)!
                )
            } else {
                metaphorWarning(message)
            }
        }
    }

    /// ヘッドレス（ウィンドウ無し）モードのレンダーループと出力を構成します。
    ///
    /// ウィンドウ/`MTKView`/ブリットパスを生成せず、常にタイマー駆動で `renderFrame()` を
    /// 回し、結果を出力 provider（Syphon 等）経由で publish します。Syphon サーバー名と FPS は
    /// 環境変数で上書きできます（`METAPHOR_SYPHON_NAME` / `METAPHOR_FPS`）。
    private func configureHeadlessLoop(config: SketchConfig) {
        guard let renderer else { return }

        let env = ProcessInfo.processInfo.environment

        // ウィンドウが無い実行が「どこにも現れない」状態にならないようにする。
        // 既定はメニューバーの状態項目（Dock は占有しない）で、`.dock` / `.both` を
        // 選んだときだけ Dock にも出す。項目そのものは出力を取り付けた後に作る
        // （出力先をメニューに出すため）。
        let indicator = Self.resolveHeadlessIndicator(config: config, env: env)
        NSApp.setActivationPolicy(indicator.showsDockIcon ? .regular : .accessory)
        if indicator.showsDockIcon {
            installMinimalMainMenu(title: config.title)
        }

        // 出力は provider の走査で決まる。ヘッドレスの観測手段は viewer socket
        // （METAPHOR_VIEWER_SOCKET → ViewerOutputPlugin）/ Probe / 明示の外部出力で、
        // Syphon を暗黙に立てることはしない（ADR-0014）。
        let outputs = MetaphorOutputProviders.makeOutputs(
            context: MetaphorOutputContext(scope: .primary(config), environment: env, isHeadless: true)
        )
        attachOutputs(outputs, renderer: renderer, env: env)
        headlessOutputPluginIDs = outputs.map { $0.plugin.pluginID }

        // FPS: 環境変数 `METAPHOR_FPS` で上書き可能（ウィンドウモードと共通）。
        let fps = Self.resolveFPS(config: config, env: env)
        renderer.targetFPS = fps

        if indicator.showsMenuBarItem {
            installHeadlessStatusItem(config: config)
        }

        // ヘッドレスは常にタイマー駆動（ディスプレイリンクは MTKView 前提のため）。
        // resolveLoopMode(isHeadless: true) も同じ答えを返す（規則は 1 箇所）。
        startTimerLoop(fps: fps)
    }

    /// ヘッドレス実行中であることを示すメニューバーの状態項目を出します。
    ///
    /// 中身はメニューを開いた瞬間に ``headlessSnapshot(config:)`` から作るので、
    /// 開いていない間はレンダーループに一切触れません。
    private func installHeadlessStatusItem(config: SketchConfig) {
        headlessIndicatorStart = CACurrentMediaTime()

        // プレビューはメニューを開いている間だけ動く（閉じている間のコストはゼロ）。
        let tap = HeadlessPreviewTap()
        renderer?.addPlugin(tap)
        headlessPreviewTap = tap
        let thumbnail = HeadlessPreviewTap.thumbnailSize(
            width: config.width, height: config.height, box: Self.headlessPreviewBox
        )

        headlessStatusItem = HeadlessStatusItem(
            snapshotProvider: { [weak self] in
                guard let self else { return Self.idleHeadlessSnapshot(config: config) }
                return self.headlessSnapshot(config: config)
            },
            previewProvider: { [weak tap] in tap?.latestFrame },
            previewSize: NSSize(width: thumbnail.width, height: thumbnail.height),
            setPreviewActive: { [weak tap] active in tap?.isCapturing = active },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    /// メニュー内プレビューを収める箱（ポイント）。実テクスチャはこの 2 倍（Retina）で作る。
    private static let headlessPreviewBox = (width: 240, height: 180)

    /// Dock に出すときだけ、空のメニューバーを避けるための最小限のメニューを組みます。
    ///
    /// `NSApplication.ActivationPolicy.regular` はアプリメニューを表示しますが、
    /// 本ライブラリは `NSApp.mainMenu` をどこでも組んでいないため、何もしないと
    /// アプリ名すら出ない空のメニューバーになります（⌘Q も効かない）。
    private func installMinimalMainMenu(title: String) {
        // AppKit は `.regular` 化の時点で「アプリメニュー 1 枚だけ・中身は空」のメニューを
        // 用意していることがある（実測）。`nil` かどうかで判定すると、その空メニューを
        // 本物と見なして ⌘Q すら効かないメニューバーが残るため、**アプリメニューの中身**で
        // 判定する。
        guard NSApp.mainMenu?.items.first?.submenu?.items.isEmpty ?? true else { return }
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: title)
        appMenu.addItem(
            withTitle: "Quit \(title)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    /// 状態項目に出す現在値を集めます（メニューを開いた瞬間に 1 回だけ）。
    ///
    /// 実測 fps は ``FrameRateTracker``、フレーム数は ``SketchContext`` から読むので、
    /// Probe / ``Sketch/performance`` / PerformanceHUD と同じ値になります。
    private func headlessSnapshot(config: SketchConfig) -> HeadlessStatusSnapshot {
        var snapshot = Self.idleHeadlessSnapshot(config: config)
        guard let renderer else { return snapshot }

        // ライブビューアは接続状態まで出す（親が落ちても子は回り続けるため、
        // 「誰も見ていない」ことがメニューから読み取れることに意味がある）。
        let viewer = renderer.plugin(id: ViewerOutputPlugin.id) as? ViewerOutputPlugin
        snapshot.outputs = headlessOutputPluginIDs.map {
            HeadlessStatusSnapshot.outputLabel(pluginID: $0, viewerConnected: viewer?.isConnected)
        }
        // Probe は出力プラグインではないが、観測者が居るかどうかの一部なので併記する。
        if renderer.plugin(id: MetaphorProbePlugin.id) != nil {
            snapshot.outputs.append("Probe")
        }

        snapshot.targetFPS = renderer.targetFPS
        snapshot.measuredFPS = renderer.frameRateTracker.windowStats(now: CACurrentMediaTime())?.fps
        snapshot.frameCount = context?.frameCount ?? 0
        snapshot.elapsed = CACurrentMediaTime() - headlessIndicatorStart
        return snapshot
    }

    /// 設定だけから作れる部分のスナップショット（動的な値は既定のまま）。
    private static func idleHeadlessSnapshot(config: SketchConfig) -> HeadlessStatusSnapshot {
        HeadlessStatusSnapshot(
            title: config.title,
            version: Metaphor.version,
            pid: ProcessInfo.processInfo.processIdentifier,
            width: config.width,
            height: config.height,
            targetFPS: config.fps,
            measuredFPS: nil,
            frameCount: 0,
            elapsed: 0,
            outputs: []
        )
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

    /// 直前のプロセスが保存した状態（`METAPHOR_RESTORE_STATE`）を適用します。
    ///
    /// - `user` ペイロードは ``Sketch/restoreState(_:)`` へ渡す（`setup()` の後）
    /// - `runtime`（時計）は ``SketchConfig/preserveClock`` が `true` のときだけ復元する
    ///
    /// 環境変数が無い・ファイルが読めない・デコードできない場合は**黙って何もしません**
    /// （開発ツールの都合でスケッチが起動しないのを避ける。CONTRACT.md 契約点 8）。
    static func applyRestoredState(
        sketch: any Sketch,
        context: SketchContext,
        renderer: MetaphorRenderer,
        config: SketchConfig,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let restored = SketchStateRestore.load(env: env) else { return }

        if let payload = restored.payload {
            sketch.restoreState(payload)
        }

        guard config.preserveClock else { return }
        // 巻き戻り（負の経過時間）は時計として無意味なので捨てる。
        context.frameCount = max(0, restored.frameCount)
        renderer.clockOffset = max(0, restored.elapsedSeconds)
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
        // 時計を引き継いだリロード（preserveClock）では時刻がオフセットぶん進んだ
        // 状態で始まるため、起点も合わせる（合わせないと初回 deltaTime が
        // 引き継いだ経過時間そのものになる）。
        // クロージャは runner を強く掴まないよう、共有の時計だけを捕捉する。
        let frameClock = self.frameClock
        frameClock.resync(to: Float(renderer.clockOffset))

        renderer.onCompute = { [weak context, weak sketch] commandBuffer, time in
            guard let context, let sketch else { return }
            let t = Float(time)
            let dt = frameClock.delta(at: t)
            context.beginCompute(commandBuffer: commandBuffer, time: t, deltaTime: dt)
            sketch.compute()
            context.endCompute()
        }

        renderer.onDraw = { [weak context, weak sketch] encoder, time in
            guard let context, let sketch else { return }
            let t = Float(time)
            let dt = frameClock.advance(to: t)
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
            let dt = frameClock.advance(to: t)
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
    ///
    /// 時計（``MetaphorRenderer/elapsedTime``）は実時間ベースで、止めている間も進みます。
    /// 一方フレームは発火しないので、起点を寄せ直さないと再開後の最初のフレームへ
    /// 「止めていた実時間まるごと」が `deltaTime` として渡り、それを積分に使う側
    /// （`Physics2D` / `TweenManager` / スケッチ自前の速度積分）が 1 回で吹き飛びます(#793)。
    /// フレームを再開する前に起点を現在時刻へ寄せ、再開後の最初の `deltaTime` を
    /// 実測どおり（＝ほぼ 1 フレームぶん）にします。
    // internal: テストから直接呼べるようにする(#793)
    func handleLoop() {
        frameClock.resync(to: Float(renderer?.elapsedTime ?? 0))
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
    /// - Parameter fps: 目標フレーム毎秒。0 以下は 1 にクランプします(#358)。
    ///   以前はこのクランプがタイマー経路の interval 計算にしか掛かっておらず、
    ///   `renderer.targetFPS`（→ Probe の `frame.json`）と
    ///   `MTKView.preferredFramesPerSecond` には無効値がそのまま渡っていた。
    ///   入口で 1 回だけクランプし、全経路へ同じ値を渡すことで揃える
    ///   （クランプ自体は ``clampedFrameRate(_:)`` が持ち、`SketchView` 経路と共有）。
    // internal: テストから直接呼べるようにする(#358)
    func handleFrameRate(_ fps: Int) {
        let clampedFPS = clampedFrameRate(fps)
        renderer?.targetFPS = clampedFPS
        if let renderTimer {
            // タイマーモード: タイマーをリスケジュール
            let interval = 1.0 / Double(clampedFPS)
            renderTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        } else {
            // ディスプレイリンクモード: MTKView の優先フレームレートを更新
            mtkView?.preferredFramesPerSecond = clampedFPS
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
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: nil, type: .moved)
        }
        input.onMouseDragged = { [weak sketch, weak renderer] x, y in
            sketch?.mouseDragged()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: nil, type: .dragged)
        }
        input.onMouseScrolled = { [weak sketch, weak renderer] dx, dy in
            sketch?.mouseScrolled()
            let mx = renderer?.input.mouseX ?? 0
            let my = renderer?.input.mouseY ?? 0
            renderer?.notifyPluginsMouseEvent(x: mx, y: my, button: nil, type: .scrolled)
        }
        input.onMouseClicked = { [weak sketch, weak renderer] x, y, button in
            sketch?.mouseClicked()
            renderer?.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .clicked)
        }
        input.onKeyDown = { [weak sketch, weak renderer] keyCode, characters in
            sketch?.keyPressed()
            if Self.producesCharacter(characters) {
                sketch?.keyTyped()
            }
            renderer?.notifyPluginsKeyEvent(key: characters?.first, keyCode: keyCode, type: .pressed)
        }
        input.onKeyUp = { [weak sketch, weak renderer] keyCode in
            sketch?.keyReleased()
            renderer?.notifyPluginsKeyEvent(key: nil, keyCode: keyCode, type: .released)
        }
        input.onFileDropInternal = { [weak sketch] paths in
            sketch?.fileDropped(paths)
        }
    }

    /// キー入力が文字を生成するか（`keyTyped()` の発火判定）。
    ///
    /// 矢印・ファンクション等の機能キーは Unicode Private Use Area
    /// U+F700–U+F8FF の文字として届くため除外する（Processing 互換）。
    nonisolated static func producesCharacter(_ characters: String?) -> Bool {
        guard let scalar = characters?.unicodeScalars.first else { return false }
        return !(0xF700...0xF8FF).contains(scalar.value)
    }
}
