/**
 * Text Particles.
 *
 * textToPoints() でグリフのアウトライン上の点を取り出し、粒子の目標地点として使う。
 * 同じアウトラインを textToContours() で線としても描き、文字が「図形」になっている
 * ことを見せる。マウスを近づけると粒子が押しのけられ、離れると元の字形へ戻る。
 */

import metaphor

@main
final class TextParticles: Sketch {

    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Text Particles")
    }

    /// 粒子。`target` は文字のアウトライン上の点。
    private struct Particle {
        var position: Vec2
        var velocity: Vec2 = .zero
        var target: Vec2
    }

    private var particles: [Particle] = []
    private var contours: [[Vec2]] = []

    func setup() {
        // 撮影・再現のために乱数を固定する
        randomSeed(42)

        textSize(96)
        textAlign(.center, .center)

        // 文字を「点の集まり」と「線の集まり」の両方として取り出す。
        // どちらも textAlign / textSize を text() と同じに解釈するので、
        // text("metaphor", cx, cy) と同じ位置に出る。
        let cx = width / 2
        let cy = height / 2
        contours = textToContours("metaphor", cx, cy, sampleFactor: 0.35)
        particles = textToPoints("metaphor", cx, cy, sampleFactor: 0.35).map { target in
            Particle(position: Vec2(random(width), random(height)), target: target)
        }
    }

    func draw() {
        background(12)

        // アウトラインそのものを薄い線で描く（粒子が集まる先の下絵）
        stroke(60)
        strokeWeight(1)
        noFill()
        for contour in contours {
            beginShape()
            for point in contour { vertex(point.x, point.y) }
            endShape(.close)
        }

        let mouse = Vec2(mouseX, mouseY)
        noStroke()
        for i in particles.indices {
            var p = particles[i]

            // 目標へのばね + マウスからの反発
            var force = (p.target - p.position) * 0.02
            let away = p.position - mouse
            let distance = max(length(away), 0.001)
            if distance < 90 {
                force += normalize(away) * (90 - distance) * 0.06
            }

            p.velocity = (p.velocity + force) * 0.86
            p.position += p.velocity
            particles[i] = p

            // 目標から離れているほど明るく（散らばりが見えるように）
            let offset = min(length(p.target - p.position) / 60, 1)
            fill(lerp(140, 255, offset), lerp(180, 210, offset), 255)
            circle(p.position.x, p.position.y, 2.4)
        }
    }
}
