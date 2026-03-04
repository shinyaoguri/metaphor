import metaphor

struct ABall {
    var x: Float
    var y: Float
    var w: Float
    var speed: Float = 0
    let gravity: Float = 0.1
    var life: Float = 255

    init(x: Float, y: Float, w: Float) {
        self.x = x; self.y = y; self.w = w
    }

    mutating func move(height: Float) {
        speed += gravity
        y += speed
        if y > height {
            speed *= -0.8
            y = height
        }
    }

    mutating func finished() -> Bool {
        life -= 1
        return life < 0
    }
}

@main
final class ArrayListClass: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ArrayListClass")
    }

    var balls: [ABall] = []
    let ballWidth: Float = 48

    func setup() {
        noStroke()
        balls.append(ABall(x: width / 2, y: 0, w: ballWidth))
    }

    func draw() {
        background(255)

        var i = balls.count - 1
        while i >= 0 {
            balls[i].move(height: height)
            fill(0, balls[i].life)
            ellipse(balls[i].x, balls[i].y, balls[i].w, balls[i].w)
            if balls[i].finished() {
                balls.remove(at: i)
            }
            i -= 1
        }
    }

    func mousePressed() {
        balls.append(ABall(x: mouseX, y: mouseY, w: ballWidth))
    }
}
