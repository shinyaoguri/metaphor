import Metal
import MetalKit
import SwiftUI

/// Sketchプロトコルを実行するランナー
@MainActor
public final class SketchRunner<S: Sketch>: ObservableObject {
    /// スケッチインスタンス
    public let sketch: S

    /// 内部のMetaphorRenderer
    public let renderer: MetaphorRenderer

    /// パイプラインキャッシュ
    private let pipelines: PipelineCache

    /// フレームカウント
    @Published public private(set) var frameCount: UInt64 = 0

    /// 入力状態
    public let inputState: InputState

    /// セットアップ完了フラグ
    private var isSetupDone = false

    /// 前フレームのマウス押下状態
    private var wasMousePressed = false

    /// 前フレームのキー押下状態
    private var wasKeyPressed = false

    /// 初期化
    public init(sketch: S) {
        self.sketch = sketch

        let (width, height) = sketch.size

        guard let renderer = MetaphorRenderer(width: width, height: height) else {
            fatalError("Failed to create MetaphorRenderer")
        }

        self.renderer = renderer
        self.inputState = InputState(
            canvasWidth: Float(width),
            canvasHeight: Float(height)
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

            let (width, height) = self.sketch.size

            // フレーム開始
            self.inputState.beginFrame()

            // Graphicsを作成
            let context = Graphics(
                encoder: encoder,
                device: self.renderer.device,
                pipelines: self.pipelines,
                width: width,
                height: height,
                frameCount: self.frameCount,
                input: self.inputState.snapshot()
            )

            // 初回のみsetup呼び出し
            if !self.isSetupDone {
                self.sketch.setup()
                self.isSetupDone = true
            }

            // マウスイベントのコールバック
            self.handleMouseCallbacks(context: context)

            // キーボードイベントのコールバック
            self.handleKeyCallbacks(context: context)

            // ユーザーの描画コード実行
            self.sketch.draw(context)

            // バッファをフラッシュ
            context.flush()

            // フレームカウント更新
            self.frameCount += 1
        }
    }

    private func handleMouseCallbacks(context: Graphics) {
        let isPressed = inputState.isMousePressed

        // マウスが押された瞬間
        if isPressed && !wasMousePressed {
            sketch.mousePressed(context)
        }

        // マウスが離された瞬間
        if !isPressed && wasMousePressed {
            sketch.mouseReleased(context)
        }

        // マウスがドラッグ中
        if isPressed && (inputState.mouseX != inputState.pmouseX || inputState.mouseY != inputState.pmouseY) {
            sketch.mouseDragged(context)
        }

        // マウスが移動（押していない状態で）
        if !isPressed && (inputState.mouseX != inputState.pmouseX || inputState.mouseY != inputState.pmouseY) {
            sketch.mouseMoved(context)
        }

        wasMousePressed = isPressed
    }

    private func handleKeyCallbacks(context: Graphics) {
        let isPressed = inputState.isKeyPressed

        // キーが押された瞬間
        if isPressed && !wasKeyPressed {
            sketch.keyPressed(context)
        }

        // キーが離された瞬間
        if !isPressed && wasKeyPressed {
            sketch.keyReleased(context)
        }

        wasKeyPressed = isPressed
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
