import metaphor

struct Snowflake {
    var x: Float
    var y: Float
    var size: Float
    var speed: Float
    var alpha: Float
    var noiseOffset: Float
}

@main
final class SnowflakesExample: Sketch {
    var flakes: [Snowflake] = []

    var config: SketchConfig {
        SketchConfig(title: "Snowflakes")
    }

    func setup() {
        for _ in 0..<200 {
            flakes.append(makeFlake(startAtTop: false))
        }
    }

    private func makeFlake(startAtTop: Bool) -> Snowflake {
        Snowflake(
            x: Float.random(in: 0...1920),
            y: startAtTop ? Float.random(in: -100...0) : Float.random(in: 0...1080),
            size: Float.random(in: 2...8),
            speed: Float.random(in: 0.5...2.5),
            alpha: Float.random(in: 0.3...1.0),
            noiseOffset: Float.random(in: 0...1000)
        )
    }

    func draw() {
        background(Color(r: 0.02, g: 0.02, b: 0.08))
        noStroke()

        for i in 0..<flakes.count {
            flakes[i].y += flakes[i].speed
            let drift = noise(flakes[i].noiseOffset + time * 0.3) - 0.5
            flakes[i].x += drift * 1.5

            if flakes[i].y > height + 10 {
                flakes[i] = makeFlake(startAtTop: true)
            }
            if flakes[i].x < -10 {
                flakes[i].x = width + 10
            } else if flakes[i].x > width + 10 {
                flakes[i].x = -10
            }

            let s = flakes[i]
            fill(Color(gray: 1.0, alpha: s.alpha))
            circle(s.x, s.y, s.size)
        }
    }
}
