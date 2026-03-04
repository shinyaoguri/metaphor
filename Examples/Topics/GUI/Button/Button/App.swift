import metaphor

@main
final class Button: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Button") }

    var rectX: Float = 0, rectY: Float = 0
    var circleX: Float = 0, circleY: Float = 0
    let rectSize: Float = 90
    let circleSize: Float = 93
    var currentR: Float = 102, currentG: Float = 102, currentB: Float = 102
    var rectOver = false, circleOver = false

    func setup() {
        circleX = width / 2 + circleSize / 2 + 10
        circleY = height / 2
        rectX = width / 2 - rectSize - 10
        rectY = height / 2 - rectSize / 2
    }

    func draw() {
        updateHover()
        background(currentR, currentG, currentB)
        if rectOver { fill(51) } else { fill(0) }
        stroke(255)
        rect(rectX, rectY, rectSize, rectSize)
        if circleOver { fill(204) } else { fill(255) }
        stroke(0)
        ellipse(circleX, circleY, circleSize, circleSize)
    }

    func updateHover() {
        let dx = circleX - mouseX, dy = circleY - mouseY
        if sqrt(dx * dx + dy * dy) < circleSize / 2 {
            circleOver = true; rectOver = false
        } else if mouseX >= rectX && mouseX <= rectX + rectSize && mouseY >= rectY && mouseY <= rectY + rectSize {
            rectOver = true; circleOver = false
        } else { rectOver = false; circleOver = false }
    }

    func mousePressed() {
        if circleOver { currentR = 255; currentG = 255; currentB = 255 }
        if rectOver { currentR = 0; currentG = 0; currentB = 0 }
    }
}
