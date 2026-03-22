import Metal

/// FPS、フレーム時間、GPU時間を表示するパフォーマンスメトリクスオーバーレイ
@MainActor
public final class PerformanceHUD {
    /// 平均化のための直近フレーム時間を格納するリングバッファ
    private var frameTimes: [Float] = []
    /// 保持するフレーム時間サンプルの最大数
    private let maxSamples = 60

    /// 平均フレームレート（fps）
    public private(set) var fps: Float = 0
    /// 平均フレーム時間（ミリ秒）
    public private(set) var frameTime: Float = 0
    /// 直近のGPU実行時間（ミリ秒）
    public private(set) var gpuTime: Float = 0

    /// 新しい PerformanceHUD インスタンスを作成します。
    public init() {}

    /// 現在のフレームのデルタタイムからメトリクスを更新します。
    /// - Parameter deltaTime: 前フレームからの経過時間（秒）。
    func update(deltaTime: Float) {
        frameTimes.append(deltaTime)
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }
        let avgDt = frameTimes.reduce(0, +) / Float(frameTimes.count)
        fps = avgDt > 0 ? 1.0 / avgDt : 0
        frameTime = avgDt * 1000 // ms
    }

    /// コマンドバッファのタイムスタンプからGPU実行時間を更新します。
    /// - Parameters:
    ///   - start: GPU開始タイムスタンプ（秒）。
    ///   - end: GPU終了タイムスタンプ（秒）。
    func updateGPUTime(start: Double, end: Double) {
        gpuTime = Float((end - start) * 1000) // ms
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
        canvas.fill(0, 0, 0, 0.6)   // 半透明の黒
        canvas.noStroke()
        let hudWidth: Float = 180
        let hudHeight: Float = 80
        let x = width - hudWidth - 10
        let y: Float = 10
        canvas.rect(x, y, hudWidth, hudHeight, 4)

        // テキスト
        canvas.fill(0, 1, 0, 1)     // 緑色のテキスト
        canvas.textSize(12)
        canvas.textAlign(.left, .top)

        let fpsStr = String(format: "FPS: %.0f", fps)
        let frameStr = String(format: "Frame: %.1f ms", frameTime)
        let gpuStr = String(format: "GPU: %.2f ms", gpuTime)

        canvas.text(fpsStr, x + 8, y + 8)
        canvas.text(frameStr, x + 8, y + 28)
        canvas.text(gpuStr, x + 8, y + 48)

        canvas.popStyle()
    }
}
