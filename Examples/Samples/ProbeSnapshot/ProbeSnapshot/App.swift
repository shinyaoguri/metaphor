import metaphor

/// Pass both "what the AI sees now" and "internal state" to an AI agent using MetaphorProbe.
///
/// After running, write a request file from another terminal like this:
/// `.metaphor/probe/current/frame.png` and `frame.json` are then written.
///
/// ```sh
/// echo '{"id":"snap-1","label":"baseline"}' > .metaphor/probe/request.json
/// ```
///
/// Each time you rewrite with a different id, that frame and state are exported in a format
/// ready for the AI to consume.
@main
final class ProbeSnapshotApp: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 640, height: 360,
            title: "Probe Snapshot Demo",
            plugins: [PluginFactory { MetaphorProbePlugin() }]
        )
    }

    func draw() {
        background(20)

        let t = Float(frameCount) * 0.02
        let cx = width / 2 + cos(t) * 80
        let cy = height / 2 + sin(t * 1.3) * 60
        let radius: Float = 40 + sin(t * 2) * 10

        noStroke()
        fill(220, 100, 140)
        circle(cx, cy, radius * 2)

        // Declare values the AI can later read from frame.json.
        // This is a complete no-op when the plugin is not registered.
        probe("circle.x", cx)
        probe("circle.y", cy)
        probe("circle.radius", radius)
        probe("phase", "orbiting")
    }
}
