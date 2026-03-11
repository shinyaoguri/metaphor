import MetaphorCore

/// A plugin that records mouse positions and draws a fading trail.
///
/// The plugin captures mouse movement via input event hooks and stores
/// positions in a ring buffer. Call ``drawTrail()`` inside your sketch's
/// ``Sketch/draw()`` to render the trail.
///
/// ```swift
/// let trail = MouseTrailPlugin(maxPoints: 100)
///
/// func setup() {
///     registerPlugin(trail)
/// }
///
/// func draw() {
///     background(0)
///     trail.drawTrail(self)
/// }
/// ```
@MainActor
public final class MouseTrailPlugin: MetaphorPlugin {
    public let pluginID = "com.metaphor.mouse-trail"

    private weak var sketch: (any Sketch)?
    private var points: [(x: Float, y: Float)] = []
    private let maxPoints: Int

    /// The trail color (RGB, 0-255). Default: white.
    public var color: (r: Float, g: Float, b: Float) = (255, 255, 255)

    /// The maximum radius of the trail circles. Default: 20.
    public var maxRadius: Float = 20

    /// Create a new mouse trail plugin.
    /// - Parameter maxPoints: The maximum number of trail points to keep.
    public init(maxPoints: Int = 80) {
        self.maxPoints = max(2, maxPoints)
    }

    public func onAttach(sketch: any Sketch) {
        self.sketch = sketch
    }

    public func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType) {
        guard type == .moved || type == .dragged else { return }

        points.append((x: x, y: y))
        if points.count > maxPoints {
            points.removeFirst()
        }
    }

    /// Draw the mouse trail. Call this inside your sketch's ``Sketch/draw()``.
    ///
    /// - Parameter sketch: The sketch to draw into.
    public func drawTrail(_ sketch: any Sketch) {
        guard points.count >= 2 else { return }

        let ctx = sketch.context
        ctx.push()
        ctx.noStroke()

        for (i, point) in points.enumerated() {
            let t = Float(i) / Float(points.count - 1)
            let alpha = t * 200
            let radius = maxRadius * t

            ctx.fill(color.r, color.g, color.b, alpha)
            ctx.ellipse(point.x, point.y, radius * 2, radius * 2)
        }

        ctx.pop()
    }
}
