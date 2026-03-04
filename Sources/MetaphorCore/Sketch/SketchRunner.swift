import AppKit
import MetalKit

/// Manages the lifecycle of a sketch.
///
/// Acts as an `NSApplicationDelegate` and programmatically constructs
/// the window, `MTKView`, and renderer. Users do not interact with
/// this class directly.
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

    // MARK: - Entry Point

    /// Launches the application with the given sketch type.
    ///
    /// Creates an `NSApplication`, instantiates the sketch, and starts
    /// the run loop.
    ///
    /// - Parameter sketchType: The concrete `Sketch` type to instantiate and run.
    static func run(sketchType: any Sketch.Type) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let runner = SketchRunner()
        app.delegate = runner

        // Create sketch instance
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
        true
    }

    // MARK: - Setup

    /// Configures the window, renderer, canvases, and render loop for the given sketch.
    ///
    /// - Parameter sketch: The sketch instance whose configuration drives window and renderer setup.
    private func setupWindow(sketch: any Sketch) {
        let config = sketch.config

        // Initialize renderer + canvases
        let renderer: MetaphorRenderer
        let canvas: Canvas2D
        let canvas3D: Canvas3D
        do {
            renderer = try MetaphorRenderer(width: config.width, height: config.height)
            canvas = try Canvas2D(renderer: renderer)
            canvas3D = try Canvas3D(renderer: renderer)
        } catch {
            showErrorAlert(error: error)
            return
        }
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
        precondition(sketch._context == nil, "Only one Sketch instance is supported at a time")
        sketch._context = context

        // createCanvas callback (allows resizing from within setup())
        context.onCreateCanvas = { [weak self] width, height in
            self?.handleCreateCanvas(width: width, height: height, config: config)
        }

        // Animation control callbacks
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

        // Window size
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
        window.contentView = mtkView
        self.mtkView = mtkView

        // Determine render loop mode.
        // If syphonName is set but renderLoopMode is still displayLink,
        // automatically switch to timer mode for Syphon compatibility.
        let loopMode: RenderLoopMode
        if config.syphonName != nil && config.renderLoopMode == .displayLink {
            loopMode = .timer(fps: config.fps)
        } else {
            loopMode = config.renderLoopMode
        }

        // Legacy Syphon support
        if let syphonName = config.syphonName {
            renderer.startSyphonServer(name: syphonName)
        }

        // Configure render loop
        switch loopMode {
        case .displayLink:
            mtkView.preferredFramesPerSecond = config.fps
            mtkView.isPaused = false

        case .timer(let fps):
            // Decouple rendering from the display link
            renderer.useExternalRenderLoop = true

            // MTKView: display link serves only as preview (throttling is acceptable)
            mtkView.preferredFramesPerSecond = fps
            mtkView.isPaused = false

            // Disable App Nap for consistent frame rate
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Timer-based render loop requires consistent frame rate"
            )

            // DispatchSourceTimer: drives renderFrame() independently of display link
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

        // Connect input callbacks to sketch event methods
        connectInput(sketch: sketch, input: renderer.input)

        // Temporarily suppress noLoop handler during setup() to prevent
        // premature pausing before onDraw is configured.
        context.onNoLoop = nil

        // setup()
        sketch.setup()

        // Restore noLoop handler
        context.onNoLoop = { [weak self] in
            self?.handleNoLoop()
        }

        // Compute phase + draw loop
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

        // If noLoop() was called during setup(), the render loop is still
        // running (handler was suppressed). Wrap onDraw to let one frame
        // render, then pause.
        if !context.isLooping {
            let userOnDraw = renderer.onDraw
            renderer.onDraw = { [weak self, weak renderer] encoder, time in
                userOnDraw?(encoder, time)
                renderer?.onDraw = userOnDraw
                self?.handleNoLoop()
            }
        }

        // Show the window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Enter full screen if configured
        if config.fullScreen {
            window.toggleFullScreen(nil)
        }
    }

    // MARK: - Animation Control

    /// Resumes the render loop.
    private func handleLoop() {
        if let renderTimer {
            renderTimer.resume()
        } else {
            mtkView?.isPaused = false
        }
    }

    /// Pauses the render loop.
    private func handleNoLoop() {
        if let renderTimer {
            renderTimer.suspend()
        } else {
            mtkView?.isPaused = true
        }
    }

    /// Triggers a single-frame redraw.
    private func handleRedraw() {
        if renderTimer != nil {
            // Timer mode: render exactly one frame
            renderer?.renderFrame()
        } else {
            // Display link mode: request a single frame draw from MTKView
            mtkView?.isPaused = false
            DispatchQueue.main.async { [weak self] in
                self?.mtkView?.isPaused = !(self?.context?.isLooping ?? true)
            }
        }
    }

    /// Updates the frame rate of the render loop.
    ///
    /// - Parameter fps: The target frames per second.
    private func handleFrameRate(_ fps: Int) {
        if let renderTimer {
            // Timer mode: reschedule the timer
            renderTimer.suspend()
            let interval = 1.0 / Double(max(fps, 1))
            renderTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
            if context?.isLooping ?? true {
                renderTimer.resume()
            }
        } else {
            // Display link mode: update MTKView's preferred frame rate
            mtkView?.preferredFramesPerSecond = fps
        }
    }

    /// Rebuilds textures, canvases, and the window to match a new canvas size.
    ///
    /// - Parameters:
    ///   - width: The new canvas width in pixels.
    ///   - height: The new canvas height in pixels.
    ///   - config: The sketch configuration used for window scale calculation.
    private func handleCreateCanvas(width: Int, height: Int, config: SketchConfig) {
        guard let renderer, let context else { return }

        // Resize textures
        renderer.resizeCanvas(width: width, height: height)

        // Rebuild Canvas2D / Canvas3D
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

        // Update window size
        let windowWidth = CGFloat(Float(width) * config.windowScale)
        let windowHeight = CGFloat(Float(height) * config.windowScale)
        window?.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window?.contentAspectRatio = NSSize(width: width, height: height)
        window?.center()
    }

    /// Displays an error alert and terminates the application.
    ///
    /// - Parameter error: The initialization error to present to the user.
    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "metaphor initialization failed"
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    /// Connects input manager callbacks to the sketch's event methods.
    ///
    /// - Parameters:
    ///   - sketch: The sketch instance that receives input events.
    ///   - input: The input manager providing raw input callbacks.
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
        input.onMouseScrolled = { [weak sketch] _, _ in
            sketch?.mouseScrolled()
        }
        input.onKeyDown = { [weak sketch] _, _ in
            sketch?.keyPressed()
        }
        input.onKeyUp = { [weak sketch] _ in
            sketch?.keyReleased()
        }
    }
}
