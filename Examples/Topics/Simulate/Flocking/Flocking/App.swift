import metaphor

struct Boid {
    var px: Float, py: Float
    var vx: Float, vy: Float
    var ax: Float = 0, ay: Float = 0
    let r: Float = 2
    let maxspeed: Float = 2
    let maxforce: Float = 0.03
}

@main
final class Flocking: Sketch {
    var config: SketchConfig { SketchConfig(title: "Flocking", width: 640, height: 360) }

    var boids: [Boid] = []

    func setup() {
        for _ in 0..<150 {
            let angle = Float.random(in: 0..<Float.pi * 2)
            boids.append(Boid(px: width / 2, py: height / 2, vx: cos(angle), vy: sin(angle)))
        }
    }

    func draw() {
        background(50)
        for i in 0..<boids.count {
            flock(i)
        }
        for i in 0..<boids.count {
            boids[i].vx += boids[i].ax; boids[i].vy += boids[i].ay
            let spd = sqrt(boids[i].vx * boids[i].vx + boids[i].vy * boids[i].vy)
            if spd > boids[i].maxspeed {
                boids[i].vx = boids[i].vx / spd * boids[i].maxspeed
                boids[i].vy = boids[i].vy / spd * boids[i].maxspeed
            }
            boids[i].px += boids[i].vx; boids[i].py += boids[i].vy
            boids[i].ax = 0; boids[i].ay = 0
            // Wraparound
            if boids[i].px < -boids[i].r { boids[i].px = width + boids[i].r }
            if boids[i].py < -boids[i].r { boids[i].py = height + boids[i].r }
            if boids[i].px > width + boids[i].r { boids[i].px = -boids[i].r }
            if boids[i].py > height + boids[i].r { boids[i].py = -boids[i].r }
            // Render
            let theta = atan2(boids[i].vy, boids[i].vx) + Float.pi / 2
            fill(200, 100)
            stroke(255)
            pushMatrix()
            translate(boids[i].px, boids[i].py)
            rotate(theta)
            beginShape(.triangles)
            vertex(0, -boids[i].r * 2)
            vertex(-boids[i].r, boids[i].r * 2)
            vertex(boids[i].r, boids[i].r * 2)
            endShape()
            popMatrix()
        }
    }

    func flock(_ i: Int) {
        var sepX: Float = 0, sepY: Float = 0, sepCount = 0
        var aliX: Float = 0, aliY: Float = 0, aliCount = 0
        var cohX: Float = 0, cohY: Float = 0, cohCount = 0
        for j in 0..<boids.count {
            let dx = boids[i].px - boids[j].px
            let dy = boids[i].py - boids[j].py
            let d = sqrt(dx * dx + dy * dy)
            if d > 0 && d < 25 {
                sepX += dx / d; sepY += dy / d; sepCount += 1
            }
            if d > 0 && d < 50 {
                aliX += boids[j].vx; aliY += boids[j].vy; aliCount += 1
                cohX += boids[j].px; cohY += boids[j].py; cohCount += 1
            }
        }
        if sepCount > 0 {
            sepX /= Float(sepCount); sepY /= Float(sepCount)
            let m = sqrt(sepX * sepX + sepY * sepY)
            if m > 0 { sepX = sepX / m * boids[i].maxspeed - boids[i].vx; sepY = sepY / m * boids[i].maxspeed - boids[i].vy }
            let sm = sqrt(sepX * sepX + sepY * sepY)
            if sm > boids[i].maxforce { sepX = sepX / sm * boids[i].maxforce; sepY = sepY / sm * boids[i].maxforce }
        }
        if aliCount > 0 {
            aliX /= Float(aliCount); aliY /= Float(aliCount)
            let m = sqrt(aliX * aliX + aliY * aliY)
            if m > 0 { aliX = aliX / m * boids[i].maxspeed - boids[i].vx; aliY = aliY / m * boids[i].maxspeed - boids[i].vy }
            let sm = sqrt(aliX * aliX + aliY * aliY)
            if sm > boids[i].maxforce { aliX = aliX / sm * boids[i].maxforce; aliY = aliY / sm * boids[i].maxforce }
        }
        if cohCount > 0 {
            cohX /= Float(cohCount); cohY /= Float(cohCount)
            var dx = cohX - boids[i].px, dy = cohY - boids[i].py
            let m = sqrt(dx * dx + dy * dy)
            if m > 0 { dx = dx / m * boids[i].maxspeed - boids[i].vx; dy = dy / m * boids[i].maxspeed - boids[i].vy }
            let sm = sqrt(dx * dx + dy * dy)
            if sm > boids[i].maxforce { dx = dx / sm * boids[i].maxforce; dy = dy / sm * boids[i].maxforce }
            cohX = dx; cohY = dy
        }
        boids[i].ax += sepX * 1.5 + aliX + cohX
        boids[i].ay += sepY * 1.5 + aliY + cohY
    }

    func mousePressed() {
        let angle = Float.random(in: 0..<Float.pi * 2)
        boids.append(Boid(px: mouseX, py: mouseY, vx: cos(angle), vy: sin(angle)))
    }
}
