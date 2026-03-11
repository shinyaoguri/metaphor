import SwiftUI
import MetalKit

/// A SwiftUI view for creative coding with closure-based drawing.
///
/// Automatically initializes `MetaphorRenderer`, `Canvas2D`, `Canvas3D`, and
/// `SketchContext`. The `draw` closure is called every frame with the active
/// context, providing full access to the drawing API.
///
/// ```swift
/// struct ContentView: View {
///     @State var radius: Float = 100
///
///     var body: some View {
///         VStack {
///             SketchView { ctx in
///                 ctx.background(.black)
///                 ctx.fill(.white)
///                 ctx.circle(ctx.width / 2, ctx.height / 2, radius)
///             }
///             Slider(value: $radius, in: 10...400)
///         }
///     }
/// }
/// ```
public struct SketchView: NSViewRepresentable {
    private let config: SketchConfig
    private let setupClosure: (@MainActor (SketchContext) -> Void)?
    private let drawClosure: @MainActor (SketchContext) -> Void

    /// Create a new sketch view with optional setup and required draw closures.
    ///
    /// - Parameters:
    ///   - config: The sketch configuration (resolution, frame rate, etc.).
    ///   - setup: An optional closure called once before the first frame.
    ///   - draw: A closure called every frame with the active ``SketchContext``.
    public init(
        config: SketchConfig = SketchConfig(),
        setup: (@MainActor (SketchContext) -> Void)? = nil,
        draw: @escaping @MainActor (SketchContext) -> Void
    ) {
        self.config = config
        self.setupClosure = setup
        self.drawClosure = draw
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(config: config, setup: setupClosure, draw: drawClosure)
    }

    public func makeNSView(context: Context) -> MetaphorMTKView {
        let coordinator = context.coordinator
        let view = MetaphorMTKView()

        do {
            try coordinator.initialize(view: view)
        } catch {
            metaphorWarning("SketchView initialization failed: \(error)")
        }

        return view
    }

    public func updateNSView(_ nsView: MetaphorMTKView, context: Context) {
        // SwiftUI state changes are automatically captured by the draw closure
        // on the next frame, so no explicit update is needed here.
    }

    // MARK: - Coordinator

    /// Manages the renderer lifecycle and frame callbacks for the SwiftUI view.
    @MainActor
    public class Coordinator {
        private let config: SketchConfig
        private let setupClosure: (@MainActor (SketchContext) -> Void)?
        private let drawClosure: @MainActor (SketchContext) -> Void

        private var renderer: MetaphorRenderer?
        private var sketchContext: SketchContext?
        private var hasCalledSetup = false

        init(
            config: SketchConfig,
            setup: (@MainActor (SketchContext) -> Void)?,
            draw: @escaping @MainActor (SketchContext) -> Void
        ) {
            self.config = config
            self.setupClosure = setup
            self.drawClosure = draw
        }

        func initialize(view: MetaphorMTKView) throws {
            let renderer = try MetaphorRenderer(
                width: config.width,
                height: config.height
            )
            let canvas = try Canvas2D(renderer: renderer)
            let canvas3D = try Canvas3D(renderer: renderer)
            let context = SketchContext(
                renderer: renderer,
                canvas: canvas,
                canvas3D: canvas3D,
                input: renderer.input
            )

            self.renderer = renderer
            self.sketchContext = context

            // Configure the view
            view.preferredFramesPerSecond = config.fps
            view.enableSetNeedsDisplay = false
            view.isPaused = false
            renderer.configure(view: view)

            // Wire up frame callbacks
            var prevTime: Float = 0

            renderer.onDraw = { [weak self] encoder, time in
                guard let self, let ctx = self.sketchContext else { return }
                let t = Float(time)
                let dt = t - prevTime
                prevTime = t

                // Call setup once on first frame
                if !self.hasCalledSetup {
                    self.setupClosure?(ctx)
                    self.hasCalledSetup = true
                }

                ctx.beginFrame(encoder: encoder, time: t, deltaTime: dt)
                self.drawClosure(ctx)
                ctx.endFrame()
            }

            renderer.onAfterDraw = { [weak context] commandBuffer in
                guard let context else { return }
                context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
            }
        }
    }
}
