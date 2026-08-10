import metaphor

/// Keep a simulation (and the clock) alive across a live-reload.
///
/// `metaphor watch` rebuilds and relaunches the sketch on every save, so by
/// default the particles below would start from scratch and `time` would jump
/// back to zero. Two opt-ins prevent that:
///
/// - `saveState()` / `restoreState(_:)` carry whatever you decide to keep
/// - `preserveClock: true` carries `frameCount` and `time` — no code needed
///
/// Try it: run `metaphor watch` in this directory, let the swarm build up, then
/// edit a color or a constant below and save. The particles keep flying and the
/// on-screen clock keeps counting.
///
/// The state travels through `.metaphor/state/state.json`, so you can also
/// trigger a save by hand:
///
/// ```sh
/// echo '{"id":"save-1"}' > .metaphor/state/save-request.json
/// ```
@main
final class StatePreservationApp: Sketch {

    /// One particle of the swarm. `Codable` is all `encodeState` needs.
    struct Particle: Codable {
        var x: Float
        var y: Float
        var vx: Float
        var vy: Float
        var hue: Float
    }

    /// Everything worth surviving a reload. Keeping it in one `Codable` struct
    /// means adding a field later is a one-line change on both sides.
    struct SavedState: Codable {
        var particles: [Particle]
        var reloads: Int
    }

    private var particles: [Particle] = []
    /// How many times this sketch has been restored — proof that the state moved.
    private var reloads = 0

    var config: SketchConfig {
        SketchConfig(width: 900, height: 600, title: "State Preservation", preserveClock: true)
    }

    // MARK: - State hooks

    func saveState() -> Data? {
        encodeState(SavedState(particles: particles, reloads: reloads))
    }

    func restoreState(_ data: Data) {
        // A failed decode (the shape changed while editing) leaves the sketch in
        // its initial state instead of crashing — that is the intended default.
        guard let state: SavedState = decodeState(data) else { return }
        particles = state.particles
        reloads = state.reloads + 1
    }

    // MARK: - Sketch

    func setup() {
        // Only seeds the very first run: after a reload `restoreState(_:)` runs
        // right after `setup()` and replaces this swarm with the saved one.
        for _ in 0..<180 { particles.append(makeParticle()) }
    }

    func draw() {
        background(14)

        noStroke()
        for index in particles.indices {
            step(&particles[index])
            let p = particles[index]
            fill(color(for: p.hue))
            circle(p.x, p.y, 6)
        }

        drawHUD()
    }

    // MARK: - Simulation

    private func makeParticle() -> Particle {
        Particle(
            x: random(width),
            y: random(height),
            vx: random(-90, 90),
            vy: random(-90, 90),
            hue: random(1)
        )
    }

    /// Moves a particle and bounces it off the edges.
    private func step(_ p: inout Particle) {
        p.x += p.vx * deltaTime
        p.y += p.vy * deltaTime
        if p.x < 0 || p.x > width { p.vx = -p.vx }
        if p.y < 0 || p.y > height { p.vy = -p.vy }
        p.x = constrain(p.x, 0, width)
        p.y = constrain(p.y, 0, height)
    }

    private func color(for hue: Float) -> Color {
        Color(r: 0.35 + hue * 0.65, g: 0.55, b: 1.0 - hue * 0.5, a: 1.0)
    }

    /// Shows the two things a reload normally resets.
    private func drawHUD() {
        fill(.white)
        textSize(16)
        text("particles: \(particles.count)", 20, 32)
        text("frameCount: \(frameCount)   time: \(String(format: "%.1f", time))s", 20, 56)
        text("restored \(reloads) time(s)", 20, 80)
    }
}
