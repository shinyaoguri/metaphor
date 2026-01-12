import Metal
import simd

/// クロージャベースの簡易スケッチ設定
/// Processing風のセットアップ・描画ループを提供
public struct QuickSketchConfig {
    public let width: Int
    public let height: Int
    public var setup: (() -> Void)?
    public var draw: ((Graphics) -> Void)?

    public init(width: Int = 1920, height: Int = 1080) {
        self.width = width
        self.height = height
    }

    /// セットアップクロージャを設定
    public func setup(_ closure: @escaping () -> Void) -> QuickSketchConfig {
        var copy = self
        copy.setup = closure
        return copy
    }

    /// 描画クロージャを設定
    public func draw(_ closure: @escaping (Graphics) -> Void) -> QuickSketchConfig {
        var copy = self
        copy.draw = closure
        return copy
    }
}

/// QuickSketchの実行を管理するクラス
@MainActor
public final class QuickSketchRunner: ObservableObject {
    /// 内部のMetaphorRenderer
    public let renderer: MetaphorRenderer

    /// パイプラインキャッシュ
    private let pipelines: PipelineCache

    /// フレームカウント
    @Published public private(set) var frameCount: UInt64 = 0

    /// 入力状態
    public let inputState: InputState

    /// 設定
    private let config: QuickSketchConfig

    /// セットアップ完了フラグ
    private var isSetupDone = false

    /// 初期化
    public init(config: QuickSketchConfig) {
        self.config = config

        guard let renderer = MetaphorRenderer(
            width: config.width,
            height: config.height
        ) else {
            fatalError("Failed to create MetaphorRenderer")
        }

        self.renderer = renderer
        self.inputState = InputState(
            canvasWidth: Float(config.width),
            canvasHeight: Float(config.height)
        )

        do {
            self.pipelines = try PipelineCache(device: renderer.device)
        } catch {
            fatalError("Failed to create PipelineCache: \(error)")
        }

        setupDrawCallback()
    }

    private func setupDrawCallback() {
        renderer.onDraw = { [weak self] encoder, _ in
            guard let self = self else { return }

            // フレーム開始
            self.inputState.beginFrame()

            // 初回のみsetup呼び出し
            if !self.isSetupDone {
                self.config.setup?()
                self.isSetupDone = true
            }

            // Graphicsを作成
            let context = Graphics(
                encoder: encoder,
                device: self.renderer.device,
                pipelines: self.pipelines,
                width: self.config.width,
                height: self.config.height,
                frameCount: self.frameCount,
                input: self.inputState.snapshot()
            )

            // ユーザーの描画コード実行
            self.config.draw?(context)

            // バッファをフラッシュ
            context.flush()

            // フレームカウント更新
            self.frameCount += 1
        }
    }

    // MARK: - Input Handling

    /// マウス位置を更新
    public func updateMousePosition(viewX: CGFloat, viewY: CGFloat, viewWidth: CGFloat, viewHeight: CGFloat) {
        inputState.updateMousePosition(
            viewX: viewX,
            viewY: viewY,
            viewWidth: viewWidth,
            viewHeight: viewHeight
        )
    }

    /// マウスボタンが押された
    public func mouseDown(button: MouseButton = .left) {
        inputState.mouseDown(button: button)
    }

    /// マウスボタンが離された
    public func mouseUp() {
        inputState.mouseUp()
    }

    /// キーが押された
    public func keyDown(character: Character, keyCode: UInt16) {
        inputState.keyDown(character: character, keyCode: keyCode)
    }

    /// キーが離された
    public func keyUp() {
        inputState.keyUp()
    }

    // MARK: - Syphon

    /// Syphonサーバーを開始
    public func startSyphon(name: String) {
        renderer.startSyphonServer(name: name)
    }

    /// Syphonサーバーを停止
    public func stopSyphon() {
        renderer.stopSyphonServer()
    }
}
