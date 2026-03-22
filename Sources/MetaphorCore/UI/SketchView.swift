import SwiftUI
import MetalKit

/// クロージャベースの描画によるクリエイティブコーディング用 SwiftUI ビュー
///
/// `MetaphorRenderer`、`Canvas2D`、`Canvas3D`、`SketchContext` を自動的に初期化します。
/// `draw` クロージャが毎フレーム呼び出され、アクティブなコンテキストを通じて
/// 描画APIへのフルアクセスを提供します。
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

    /// オプションの setup と必須の draw クロージャで新しいスケッチビューを作成します。
    ///
    /// - Parameters:
    ///   - config: スケッチの設定（解像度、フレームレートなど）。
    ///   - setup: 最初のフレームの前に一度だけ呼ばれるオプションのクロージャ。
    ///   - draw: 毎フレーム呼ばれるクロージャ。アクティブな ``SketchContext`` が渡されます。
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
        // SwiftUI の状態変更は次フレームで draw クロージャにより自動的にキャプチャされるため、
        // ここでの明示的な更新は不要です。
    }

    // MARK: - Coordinator

    /// SwiftUI ビューのレンダラーライフサイクルとフレームコールバックを管理します。
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

            // ビューを設定
            view.preferredFramesPerSecond = config.fps
            view.enableSetNeedsDisplay = false
            view.isPaused = false
            renderer.configure(view: view)

            // フレームコールバックを接続
            var prevTime: Float = 0

            renderer.onDraw = { [weak self] encoder, time in
                guard let self, let ctx = self.sketchContext else { return }
                let t = Float(time)
                let dt = t - prevTime
                prevTime = t

                // 初回フレームで setup を呼び出し
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
