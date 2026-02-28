import AppKit
import MetalKit

/// Sketchのライフサイクルを管理するランナー
///
/// NSApplicationDelegateとして動作し、ウィンドウ・MTKView・レンダラーを
/// プログラマティックに構築する。ユーザーはこのクラスを直接使わない。
@MainActor
final class SketchRunner: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var mtkView: MetaphorMTKView?
    private var renderer: MetaphorRenderer?
    private var canvas: Canvas2D?
    private var canvas3D: Canvas3D?
    private var context: SketchContext?
    private var sketchRef: (any Sketch)?

    // MARK: - Entry Point

    static func run(sketchType: any Sketch.Type) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let runner = SketchRunner()
        app.delegate = runner

        // Sketchインスタンスを作成
        let sketch = sketchType.init()
        runner.sketchRef = sketch

        app.run()
    }

    // MARK: - NSApplicationDelegate

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let sketch = sketchRef else { return }
            setupWindow(sketch: sketch)
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Setup

    private func setupWindow(sketch: any Sketch) {
        let config = sketch.config

        // レンダラー
        guard let renderer = MetaphorRenderer(width: config.width, height: config.height) else {
            fatalError("Failed to create MetaphorRenderer")
        }
        self.renderer = renderer

        // Canvas2D
        guard let canvas = try? Canvas2D(renderer: renderer) else {
            fatalError("Failed to create Canvas2D")
        }
        self.canvas = canvas

        // Canvas3D
        guard let canvas3D = try? Canvas3D(renderer: renderer) else {
            fatalError("Failed to create Canvas3D")
        }
        self.canvas3D = canvas3D

        // SketchContext
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        self.context = context
        _activeSketchContext = context

        // ウィンドウサイズ
        let windowWidth = CGFloat(Float(config.width) * config.windowScale)
        let windowHeight = CGFloat(Float(config.height) * config.windowScale)

        let windowRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = config.title
        window.center()
        self.window = window

        // MTKView
        let mtkView = MetaphorMTKView()
        mtkView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        mtkView.preferredFramesPerSecond = config.fps
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        renderer.configure(view: mtkView)
        window.contentView = mtkView
        self.mtkView = mtkView

        // Syphon
        if let syphonName = config.syphonName {
            renderer.startSyphonServer(name: syphonName)
        }

        // 入力コールバック → Sketchイベント
        connectInput(sketch: sketch, input: renderer.input)

        // setup()
        sketch.setup()

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
            sketch.draw(context)
            context.endFrame()
        }

        // ウィンドウ表示
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func connectInput(sketch: any Sketch, input: InputManager) {
        input.onMousePressed = { [weak sketch] _, _, _ in
            sketch?.mousePressed()
        }
        input.onMouseReleased = { [weak sketch] _, _, _ in
            sketch?.mouseReleased()
        }
        input.onMouseMoved = { [weak sketch] _, _ in
            sketch?.mouseMoved()
        }
        input.onMouseDragged = { [weak sketch] _, _ in
            sketch?.mouseDragged()
        }
        input.onKeyDown = { [weak sketch] _, _ in
            sketch?.keyPressed()
        }
        input.onKeyUp = { [weak sketch] _ in
            sketch?.keyReleased()
        }
    }
}
