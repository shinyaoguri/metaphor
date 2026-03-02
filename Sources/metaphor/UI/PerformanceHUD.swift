import Metal

/// パフォーマンスメトリクスのオーバーレイ表示
@MainActor
public final class PerformanceHUD {
    // Ring buffer for FPS averaging
    private var frameTimes: [Float] = []
    private let maxSamples = 60

    // Metrics
    public private(set) var fps: Float = 0
    public private(set) var frameTime: Float = 0
    public private(set) var gpuTime: Float = 0

    public init() {}

    /// Update metrics from deltaTime
    func update(deltaTime: Float) {
        frameTimes.append(deltaTime)
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }
        let avgDt = frameTimes.reduce(0, +) / Float(frameTimes.count)
        fps = avgDt > 0 ? 1.0 / avgDt : 0
        frameTime = avgDt * 1000 // ms
    }

    /// Update GPU time from command buffer
    func updateGPUTime(start: Double, end: Double) {
        gpuTime = Float((end - start) * 1000) // ms
    }

    /// Draw the HUD overlay using Canvas2D
    func draw(canvas: Canvas2D, width: Float, height: Float) {
        // Save style
        canvas.pushStyle()

        // Background
        canvas.fill(0, 0, 0, 0.6)   // semi-transparent black
        canvas.noStroke()
        let hudWidth: Float = 180
        let hudHeight: Float = 80
        let x = width - hudWidth - 10
        let y: Float = 10
        canvas.rect(x, y, hudWidth, hudHeight, 4)

        // Text
        canvas.fill(0, 1, 0, 1)     // green text
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
