import metaphor

@main
final class MouseFunctions: Sketch {
    var bx: Float = 0
    var by: Float = 0
    let boxSize: Float = 75
    var overBox = false
    var locked = false
    var xOffset: Float = 0
    var yOffset: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Mouse Functions") }
    func setup() {
        bx = width / 2
        by = height / 2
        rectMode(.radius)
    }
    func draw() {
        background(0)
        if mouseX > bx - boxSize && mouseX < bx + boxSize &&
           mouseY > by - boxSize && mouseY < by + boxSize {
            overBox = true
            if !locked {
                stroke(255)
                fill(153)
            }
        } else {
            stroke(153)
            fill(153)
            overBox = false
        }
        rect(bx, by, boxSize, boxSize)
    }
    func mousePressed() {
        if overBox {
            locked = true
            fill(255)
        } else {
            locked = false
        }
        xOffset = mouseX - bx
        yOffset = mouseY - by
    }
    func mouseDragged() {
        if locked {
            bx = mouseX - xOffset
            by = mouseY - yOffset
        }
    }
    func mouseReleased() {
        locked = false
    }
}
