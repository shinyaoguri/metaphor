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

    private let renderer: MetaphorRenderer
    private var window: NSWindow?
    private var mtkView: MetaphorMTKView?
    private var windowDelegate: WindowDelegate?
    private var drawClosure: ((@MainActor (SketchContext) -> Void))?
    private var prevTime: Float = 0
    private var renderTimer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?

    private static var windowCounter: Int = 0

    // MARK: - Initialization

    init(config: SketchWindowConfig, sharedResources: SharedMetalResources) throws {
        self.config = config

        let renderer = try MetaphorRenderer(
            sharedResources: sharedResources,
            width: config.width,
            height: config.height
        )
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

        setupWindow()
        setupRenderLoop()
        connectInput()

        if let syphonName = config.syphonName {
            renderer.startSyphonServer(name: syphonName)
        }
    }

    // MARK: - Drawing API

    /// クロージャを使用してこのウィンドウに描画します。
    ///
    /// 親スケッチの `draw()` メソッドから毎フレーム呼び出してください。
    /// クロージャはこのウィンドウの ``SketchContext`` をフル描画 API で受け取ります。
    ///
    /// - Parameter closure: 描画操作を行うクロージャ。
    public func draw(_ closure: @escaping @MainActor (SketchContext) -> Void) {
        guard isOpen else { return }
        drawClosure = closure
    }

    /// 毎フレーム自動実行される永続的な描画クロージャを設定します。
    ///
    /// ``draw(_:)`` とは異なり、親スケッチの `draw()` から毎フレーム
    /// 呼び出す必要なく、フレームを跨いで永続します。
    ///
    /// - Parameter closure: 毎フレーム描画操作を行うクロージャ。
    public func onDraw(_ closure: @escaping @MainActor (SketchContext) -> Void) {
        drawClosure = closure
    }

    /// このウィンドウを閉じリソースを解放します。
    public func close() {
        guard isOpen else { return }
        stopRenderTimer()
        isOpen = false
        drawClosure = nil
        window?.close()
        window = nil
        mtkView = nil
        windowDelegate = nil
    }

    // MARK: - Private Setup

    private func setupWindow() {
        let windowWidth = CGFloat(Float(config.width) * config.windowScale)
        let windowHeight = CGFloat(Float(config.height) * config.windowScale)

        let windowRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        let win = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = config.title
        win.contentAspectRatio = NSSize(width: config.width, height: config.height)
        win.center()

        // ウィンドウを重ならないようにカスケード
        let offset = CGFloat(30 * SketchWindow.windowCounter)
        win.setFrameOrigin(NSPoint(
            x: win.frame.origin.x + offset,
            y: win.frame.origin.y - offset
        ))
        SketchWindow.windowCounter += 1

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

    private func setupRenderLoop() {
        // レンダーループモードの決定。
        // syphonName が設定されているが renderLoopMode が displayLink のままの場合、
        // Syphon 互換性のため自動的にタイマーモードに切り替え。
        let loopMode: RenderLoopMode
        if config.syphonName != nil && config.renderLoopMode == .displayLink {
            loopMode = .timer(fps: config.fps)
        } else {
            loopMode = config.renderLoopMode
        }

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

    private func handleWindowClose() {
        stopRenderTimer()
        isOpen = false
        drawClosure = nil
        mtkView = nil
        window = nil
        windowDelegate = nil
    }

    private func stopRenderTimer() {
        if let renderTimer {
            renderTimer.cancel()
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
