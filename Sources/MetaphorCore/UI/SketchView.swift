import SwiftUI
import MetalKit

/// クロージャベースの描画によるクリエイティブコーディング用 SwiftUI ビュー
///
/// `MetaphorRenderer`、`Canvas2D`、`Canvas3D`、`SketchContext` を自動的に初期化します。
/// `draw` クロージャが毎フレーム呼び出され、アクティブなコンテキストを通じて
/// 描画APIへのフルアクセスを提供します。
///
/// ``SketchContext/loop()`` / ``SketchContext/noLoop()`` / ``SketchContext/redraw()`` /
/// ``SketchContext/frameRate(_:)`` によるアニメーション制御も、スタンドアロン実行
/// （`Sketch` プロトコル）と同じように効きます(#808)。
///
/// setup クロージャ内の ``SketchContext/createCanvas(width:height:)`` も効きます(#828)。
/// ただしこの経路が作り直すのは**レンダリング解像度（オフスクリーンテクスチャ）だけ**で、
/// ビューの寸法は SwiftUI のレイアウトが決めます。画面への転送は従来どおりアスペクト比を
/// 保つため、指定した比率とビューの比率が食い違えばレターボックス/ピラーボックスになります。
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

        // internal: テストから配線の効き（isPaused / targetFPS / deltaTime の起点）を
        // 検証できるようにする(#808)
        private(set) var renderer: MetaphorRenderer?
        private(set) var sketchContext: SketchContext?

        /// setup() 内で `noLoop()` が呼ばれたときに立てる「初回フレームを描き切ってから
        /// 止める」印(#828)。setup はフレームの外で走るので、その場で `isPaused` を立てると
        /// 1 フレームも描かれないまま止まってしまう。
        private var pauseAfterFirstFrame = false

        /// フレーム時刻の起点。``SketchContext/loop()`` での再開時に寄せ直し、
        /// 止めていた実時間まるごとが 1 フレームぶんの `deltaTime` に化けるのを防ぎます(#793)。
        private let frameClock = FrameClock()

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
            canvas.onSetClearColor = { [weak renderer] r, g, b, a in
                renderer?.setClearColor(r, g, b, a)
            }
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

            // アニメーション制御コールバック（SketchRunner のディスプレイリンク経路と同じ挙動。
            // この経路はタイマーモードを持たないので、MTKView の一時停止だけで止め方が足りる）
            context.onLoop = { [weak self, weak view] in
                guard let self else { return }
                // 時計は止めている間も進むので、フレームを再開する前に起点を寄せ直す(#793)
                self.frameClock.resync(to: Float(self.renderer?.elapsedTime ?? 0))
                view?.isPaused = false
                self.renderer?.notifyPluginsStart()
            }
            // setup() の間だけ外すため、ハンドラは名前を付けて持っておく(#828)
            let noLoopHandler: () -> Void = { [weak self, weak view] in
                view?.isPaused = true
                self?.renderer?.notifyPluginsStop()
            }
            context.onNoLoop = noLoopHandler
            context.onRedraw = { [weak view] in
                // MTKView.draw() は draw(in:) を同期的に呼び、renderFrame() とブリットを
                // ちょうど 1 回ずつ実行する（isPaused のトグルより時点が確かめやすい）
                view?.draw()
            }
            context.onFrameRate = { [weak self, weak view] fps in
                let clampedFPS = clampedFrameRate(fps)
                self?.renderer?.targetFPS = clampedFPS
                view?.preferredFramesPerSecond = clampedFPS
            }

            // キャンバスリサイズのコールバック（setup() 内での createCanvas() を許可、#828）。
            // SketchRunner.handleCreateCanvas と同じ手順から、ウィンドウ操作だけを落とした形。
            // この経路のビュー寸法は SwiftUI が決めるので作り直すのはオフスクリーンだけで、
            // 画面へのブリットは毎フレーム textureManager.aspectRatio を引き直すため自動で追随する。
            context.onCreateCanvas = { [weak self] width, height in
                self?.handleCreateCanvas(width: width, height: height)
            }

            // フレームコールバックを接続
            renderer.onDraw = { [weak self, weak view] encoder, time in
                guard let self, let ctx = self.sketchContext else { return }
                let t = Float(time)
                let dt = self.frameClock.advance(to: t)

                ctx.beginFrame(encoder: encoder, time: t, deltaTime: dt)
                self.drawClosure(ctx)
                ctx.endFrame()

                // setup() 内の noLoop() はここまで持ち越して止める(#828)。
                if self.pauseAfterFirstFrame {
                    self.pauseAfterFirstFrame = false
                    view?.isPaused = true
                    self.renderer?.notifyPluginsStop()
                }
            }

            renderer.onAfterDraw = { [weak context] commandBuffer in
                guard let context else { return }
                context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
            }

            // setup() はフレームの外で呼ぶ(#828)。SketchRunner が setupCore で
            // 描画コールバックを構成する前に sketch.setup() を呼ぶのと同じ位置づけ。
            // createCanvas() が通る MetaphorRenderer.resizeCanvas はインフライトフレームを
            // 枯らすため inflightSemaphore を 3 つ取りに行くので、renderFrame() が 1 つ
            // 掴んだままのフレーム中に呼ぶと 5 秒スタックしてタイムアウトする。
            //
            // ただし setup() 内の noLoop() をそのまま効かせると 1 フレームも描かれないまま
            // 止まるので、SketchRunner.setupCore と同じくハンドラを一時的に外し、
            // 「初回フレームを描き切ってから止める」へ読み替える。
            context.onNoLoop = nil
            setupClosure?(context)
            context.onNoLoop = noLoopHandler
            pauseAfterFirstFrame = !context.isLooping
        }

        /// テクスチャとキャンバスを新しいキャンバスサイズに合わせて再構築します(#828)。
        ///
        /// - Parameters:
        ///   - width: 新しいキャンバスの幅（ピクセル単位）。
        ///   - height: 新しいキャンバスの高さ（ピクセル単位）。
        private func handleCreateCanvas(width: Int, height: Int) {
            guard let renderer, let context = sketchContext else { return }

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
        }
    }
}
