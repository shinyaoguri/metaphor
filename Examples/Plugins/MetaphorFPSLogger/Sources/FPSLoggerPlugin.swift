import Metal
import MetaphorCore
import QuartzCore

/// A plugin that logs FPS to the console at a configurable interval.
///
/// ```swift
/// func setup() {
///     registerPlugin(FPSLoggerPlugin(interval: 60))
/// }
/// ```
@MainActor
public final class FPSLoggerPlugin: MetaphorPlugin {
    public let pluginID = "com.metaphor.fps-logger"

    private let interval: Int
    private var frameCount: Int = 0
    private var lastTime: Double = 0

    /// Create a new FPS logger plugin.
    /// - Parameter interval: Log FPS every N frames (default: 60).
    public init(interval: Int = 60) {
        self.interval = max(1, interval)
    }

    public func onAttach(sketch: any Sketch) {
        print("[FPSLoggerPlugin] attached")
    }

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        frameCount += 1

        if frameCount == 1 {
            lastTime = time
            return
        }

        if frameCount % interval == 0 {
            let elapsed = time - lastTime
            if elapsed > 0 {
                let fps = Double(interval) / elapsed
                print(String(format: "[FPS] %.1f", fps))
            }
            lastTime = time
        }
    }
}
