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
    private var activity: NSObjectProtocol?
    private var sharedResources: SharedMetalResources?

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
        setupWindow(sketch: sketch)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // プライマリウィンドウが閉じられた場合のみ終了
        !(window?.isVisible ?? false)
    }

    // MARK: - Setup

    /// 指定されたスケッチ用にウィンドウ、レンダラー、キャンバス、レンダーループを構成します。
    ///
    /// - Parameter sketch: 設定がウィンドウとレンダラーのセットアップを駆動するスケッチインスタンス。
    private func setupWindow(sketch: any Sketch) {
        let config = sketch.config

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
            return
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

        // レンダーループモードの決定。
        // syphonName が設定されているが renderLoopMode が displayLink のままの場合、
        // Syphon 互換性のため自動的にタイマーモードに切り替え。
        let loopMode: RenderLoopMode
        if config.syphonName != nil && config.renderLoopMode == .displayLink {
            loopMode = .timer(fps: config.fps)
        } else {
            loopMode = config.renderLoopMode
        }

        // レガシー Syphon サポート
        if let syphonName = config.syphonName {
            renderer.startSyphonServer(name: syphonName)
        }

        // レンダーループの構成。
        // 両モードとも、onDraw のセットアップ前に CVDisplayLink が発火する
        // 競合を避けるため、ディスプレイリンクを一時停止した状態で開始。
        // セットアップ完了後にディスプレイリンクを再開（または明示的に
        // 1フレームを描画）— このメソッドの末尾を参照。
        switch loopMode {
        case .displayLink:
            mtkView.preferredFramesPerSecond = config.fps
            mtkView.isPaused = true

        case .timer(let fps):
            // レンダリングをディスプレイリンクから分離
            renderer.useExternalRenderLoop = true

            // MTKView: ディスプレイリンクはプレビューとしてのみ使用（スロットリングは許容）
            mtkView.preferredFramesPerSecond = fps
            mtkView.isPaused = false

            // 安定したフレームレートのため App Nap を無効化
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Timer-based render loop requires consistent frame rate"
            )

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
            renderTimer = timer
        }

        // 入力コールバックをスケッチのイベントメソッドに接続
        connectInput(sketch: sketch, input: renderer.input, renderer: renderer)

        // config からプラグインを登録（setup() の前に利用可能にするため）
        for factory in config.plugins {
            let plugin = factory.create()
            renderer.addPlugin(plugin, sketch: sketch)
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

        // コンピュートフェーズ + 描画ループ
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
            context.beginFrame(encoder: encoder, time: t, deltaTime: dt)
            sketch.draw()
            context.endFrame()
        }

        renderer.onAfterDraw = { [weak context] commandBuffer in
            guard let context else { return }
            context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }

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
                renderTimer.suspend()
            }
            // 予備の（オフスクリーンのみの）フレームをレンダリングし、
            // background() がユーザーのクリアカラーをレンダーパス
            // ディスクリプタに登録。この最初のパスでは clearColorApplied が
            // まだ false なので背景クワッドが描画される。結果は画面には表示されない。
            renderer.renderFrame()
            // 2番目のフレームでは clearColorApplied == true なので、
            // background() は Metal の loadAction = .clear に上でキャプチャした
            // 色での塗りつぶしを任せる。
            let wasExternal = renderer.useExternalRenderLoop
            renderer.useExternalRenderLoop = false
            mtkView.draw()
            renderer.useExternalRenderLoop = wasExternal
        }
    }

    // MARK: - Animation Control

    /// レンダーループを再開します。
    private func handleLoop() {
        if let renderTimer {
            renderTimer.resume()
        } else {
            mtkView?.isPaused = false
        }
    }

    /// レンダーループを一時停止します。
    private func handleNoLoop() {
        if let renderTimer {
            renderTimer.suspend()
        } else {
            mtkView?.isPaused = true
        }
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
            renderTimer.suspend()
            let interval = 1.0 / Double(max(fps, 1))
            renderTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
            if context?.isLooping ?? true {
                renderTimer.resume()
            }
        } else {
            // ディスプレイリンクモード: MTKView の優先フレームレートを更新
            mtkView?.preferredFramesPerSecond = fps
        }
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
