import metaphor

@main
final class AgentToolsSketch: Sketch {
    // 外から触れる面。GUI を出していなくても、宣言した時点で外部から読み書きできる
    @Param(min: 8, max: 96) var count: Int = 40
    @Param(min: 0, max: 3) var speed: Float = 1
    @Param(min: 0, max: 160) var amplitude: Float = 70
    @Param(choices: ["dots", "bars"]) var style: String = "dots"

    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "AgentTools")
    }

    func draw() {
        background(10, 12, 18)

        let phase = Float(frameCount) * 0.02 * speed
        var peak: Float = 0

        noStroke()
        for i in 0..<count {
            let t = Float(i) / Float(max(count - 1, 1))
            let x = 40 + t * (width - 80)
            let offset = sin(phase + t * TWO_PI * 1.5) * amplitude
            let y = height / 2 + offset
            peak = max(peak, abs(offset))

            fill(Color(r: 0.35 + t * 0.5, g: 0.6, b: 1 - t * 0.3))
            if style == "bars" {
                rect(x - 4, min(y, height / 2), 8, abs(offset))
            } else {
                circle(x, y, 12)
            }
        }

        // 絵に写らない値を申告する。AI はこれを snapshot の応答で読む
        probe("wave.count", count)
        probe("wave.peak", peak)
        probe("wave.style", style)
    }
}
