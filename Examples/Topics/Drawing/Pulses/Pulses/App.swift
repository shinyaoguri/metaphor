import metaphor

@main
final class Pulses: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Pulses", width: 640, height: 360)
    }

    var angle: Float = 0

    func setup() {
        background(102)
        noStroke()
        fill(0, 102)
    }

    func draw() {
        if isMousePressed {
            angle += 5
            let val = cos(radians(angle)) * 12.0
            var a: Float = 0
            while a < 360 {
                let xoff = cos(radians(a)) * val
                let yoff = sin(radians(a)) * val
                fill(0)
                ellipse(mouseX + xoff, mouseY + yoff, val, val)
                a += 75
            }
            fill(255)
            ellipse(mouseX, mouseY, 2, 2)
        }
    }
}
