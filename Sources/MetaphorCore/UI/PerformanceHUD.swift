import Metal

/// FPS、フレーム時間、GPU時間を表示するパフォーマンスメトリクスオーバーレイ
///
/// fps とフレーム時間は ``FrameRateTracker`` の直近ウィンドウ集計をそのまま映します。
/// つまり **``Sketch/performance``（`performance.fps`）と Probe の `frame.json` の
/// `performance` と同じ採取経路**で、画面に出る数字とスケッチ／エージェントが読む数字が
/// 食い違いません（Issue #698）。GPU 時間だけはトラッカーの管轄外で、コマンドバッファの
/// タイムスタンプから直接採ります。
@MainActor
public final class PerformanceHUD {
    /// 直近ウィンドウの実測フレームレート（fps）。算出に足るフレームが無いときは `nil`。
    ///
    /// `nil` は ``Sketch/performance`` の `fps` が `nil` になる条件と同じ
    /// （起動直後・`noLoop()` で停止中）で、表示は `--` になります。
    public private(set) var fps: Float?
    /// 直近ウィンドウの平均フレーム時間（ミリ秒）。算出不能なときは `nil`。
    public private(set) var frameTime: Float?
    /// 直近のGPU実行時間（ミリ秒）
    public private(set) var gpuTime: Float = 0

    /// 新しい PerformanceHUD インスタンスを作成します。
    public init() {}

    /// 直近ウィンドウの実測値から表示を更新します。
    ///
    /// 値を自前で平均せず、``FrameRateTracker/windowStats(now:window:)`` の結果を
    /// そのまま映すことが要点です（同じ窓・同じ算出）。
    /// - Parameter stats: 直近ウィンドウの集計。算出不能なら `nil`。
    func update(stats: FrameRateTracker.WindowStats?) {
        fps = stats.map { Float($0.fps) }
        frameTime = stats.map { Float($0.frameTimeMeanMs) }
    }

    /// コマンドバッファのタイムスタンプからGPU実行時間を更新します。
    /// - Parameters:
    ///   - start: GPU開始タイムスタンプ（秒）。
    ///   - end: GPU終了タイムスタンプ（秒）。
    func updateGPUTime(start: Double, end: Double) {
        gpuTime = Float((end - start) * 1000) // ms
    }

    // MARK: - 表示文字列

    /// fps の表示。算出不能なときは `0` ではなく `--`（`noLoop()` の作品で
    /// `FPS: 0` と出すと誤情報になるため）。
    var fpsText: String {
        guard let fps else { return "FPS: --" }
        return String(format: "FPS: %.0f", fps)
    }

    /// フレーム時間の表示。算出不能なときは `--`。
    var frameTimeText: String {
        guard let frameTime else { return "Frame: -- ms" }
        return String(format: "Frame: %.1f ms", frameTime)
    }

    /// GPU 時間の表示。
    var gpuTimeText: String {
        String(format: "GPU: %.2f ms", gpuTime)
    }

    // MARK: - 見た目

    /// パネルの色（半透明の黒）。
    static let panelColor = Color(r: 0, g: 0, b: 0, alpha: 0.6)

    /// 数字の色（緑）。
    static let textColor = Color(r: 0, g: 1, b: 0, alpha: 1)

    /// パネルの塗りを適用します。
    ///
    /// HUD は画面の付属物なので、スケッチ側の `colorMode` に左右されてはいけません。
    /// チャンネル値をとる `fill(_:_:_:_:)` は `ColorModeConfig`（既定の最大値 255）を
    /// 通るため、0-1 の値で呼ぶとほぼ透明になります。``Color`` を直接渡して
    /// 変換そのものを避けます。
    static func applyPanelStyle(to canvas: Canvas2D) {
        canvas.fill(panelColor)
        canvas.noStroke()
    }

    /// 数字の塗りを適用します（``applyPanelStyle(to:)`` と同じ理由で ``Color`` を渡します）。
    static func applyTextStyle(to canvas: Canvas2D) {
        canvas.fill(textColor)
    }

    /// Canvas2D プリミティブを使用してHUDオーバーレイを描画します。
    /// - Parameters:
    ///   - canvas: 描画に使用する Canvas2D インスタンス。
    ///   - width: キャンバス幅（ピクセル）。
    ///   - height: キャンバス高さ（ピクセル）。
    func draw(canvas: Canvas2D, width: Float, height: Float) {
        // スタイルを保存
        canvas.pushStyle()

        // 背景
        Self.applyPanelStyle(to: canvas)
        let hudWidth: Float = 180
        let hudHeight: Float = 80
        let x = width - hudWidth - 10
        let y: Float = 10
        canvas.rect(x, y, hudWidth, hudHeight, 4)

        // テキスト
        Self.applyTextStyle(to: canvas)
        canvas.textSize(12)
        canvas.textAlign(.left, .top)

        canvas.text(fpsText, x + 8, y + 8)
        canvas.text(frameTimeText, x + 8, y + 28)
        canvas.text(gpuTimeText, x + 8, y + 48)

        canvas.popStyle()
    }
}
