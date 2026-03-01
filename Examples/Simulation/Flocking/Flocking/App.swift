import metaphor

struct Boid {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float

    var heading: Float { atan2(vy, vx) }
}

@main
final class FlockingExample: Sketch {
    var boids: [Boid] = []
    let maxSpeed: Float = 4
    let maxForce: Float = 0.05

    var config: SketchConfig {
        SketchConfig(title: "Flocking")
    }

    func setup() {
        for _ in 0..<150 {
            boids.append(makeBoid(Float.random(in: 0...1920), Float.random(in: 0...1080)))
        }
    }

    private func makeBoid(_ x: Float, _ y: Float) -> Boid {
        let a = Float.random(in: 0...Float.pi * 2)
        let s = Float.random(in: 2...4)
        return Boid(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s)
    }

    private func limit(_ x: inout Float, _ y: inout Float, _ max: Float) {
        let m = sqrt(x * x + y * y)
        if m > max { x = x / m * max; y = y / m * max }
    }

    func draw() {
        background(Color(r: 0.05, g: 0.05, b: 0.08))

        let w = width
        let h = height
        var next = boids

        for i in 0..<boids.count {
            var sepX: Float = 0, sepY: Float = 0, sepN = 0
            var aliX: Float = 0, aliY: Float = 0, aliN = 0
            var cohX: Float = 0, cohY: Float = 0, cohN = 0

            for j in 0..<boids.count where i != j {
                let dx = boids[j].x - boids[i].x
                let dy = boids[j].y - boids[i].y
                let d = sqrt(dx * dx + dy * dy)

                if d < 25 && d > 0 {
                    sepX -= dx / d; sepY -= dy / d; sepN += 1
                }
                if d < 50 {
                    aliX += boids[j].vx; aliY += boids[j].vy; aliN += 1
                    cohX += boids[j].x; cohY += boids[j].y; cohN += 1
                }
            }

            var ax: Float = 0, ay: Float = 0

            if sepN > 0 {
                sepX /= Float(sepN); sepY /= Float(sepN)
                let m = sqrt(sepX * sepX + sepY * sepY)
                if m > 0 {
                    var fx = (sepX / m) * maxSpeed - boids[i].vx
                    var fy = (sepY / m) * maxSpeed - boids[i].vy
                    limit(&fx, &fy, maxForce)
                    ax += fx * 1.5; ay += fy * 1.5
                }
            }
            if aliN > 0 {
                aliX /= Float(aliN); aliY /= Float(aliN)
                let m = sqrt(aliX * aliX + aliY * aliY)
                if m > 0 {
                    var fx = (aliX / m) * maxSpeed - boids[i].vx
                    var fy = (aliY / m) * maxSpeed - boids[i].vy
                    limit(&fx, &fy, maxForce)
                    ax += fx; ay += fy
                }
            }
            if cohN > 0 {
                cohX /= Float(cohN); cohY /= Float(cohN)
                var fx = cohX - boids[i].x
                var fy = cohY - boids[i].y
                let m = sqrt(fx * fx + fy * fy)
                if m > 0 {
                    fx = (fx / m) * maxSpeed - boids[i].vx
                    fy = (fy / m) * maxSpeed - boids[i].vy
                    limit(&fx, &fy, maxForce)
                    ax += fx; ay += fy
                }
            }

            var nvx = next[i].vx + ax
            var nvy = next[i].vy + ay
            limit(&nvx, &nvy, maxSpeed)
            next[i].vx = nvx; next[i].vy = nvy
            next[i].x += nvx; next[i].y += nvy

            if next[i].x < 0 { next[i].x += w }
            if next[i].x > w { next[i].x -= w }
            if next[i].y < 0 { next[i].y += h }
            if next[i].y > h { next[i].y -= h }
        }
        boids = next

        // 描画
        noStroke()
        for b in boids {
            let a = b.heading
            let hue = (a + Float.pi) / (Float.pi * 2)
            fill(Color(hue: hue, saturation: 0.7, brightness: 1.0, alpha: 0.9))

            let sz: Float = 8
            triangle(
                b.x + cos(a) * sz, b.y + sin(a) * sz,
                b.x + cos(a + 2.5) * sz * 0.5, b.y + sin(a + 2.5) * sz * 0.5,
                b.x + cos(a - 2.5) * sz * 0.5, b.y + sin(a - 2.5) * sz * 0.5
            )
        }
    }

    func mousePressed() {
        let mx = input.mouseX
        let my = input.mouseY
        for _ in 0..<10 {
            boids.append(makeBoid(
                mx + Float.random(in: -20...20),
                my + Float.random(in: -20...20)
            ))
        }
    }
}
