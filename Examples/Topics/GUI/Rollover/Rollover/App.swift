import metaphor

@main
final class Rollover: Sketch {
    var config: SketchConfig { SketchConfig(title: "Rollover", width: 640, height: 360) }

    var rectX: Float = 0, rectY: Float = 0
    var circleX: Float = 0, circleY: Float = 0
    let rectSize: Float = 90
    let circleSize: Float = 93
    var rectOver = false, circleOver = false

    func setup() {
        circleX = width / 2 + circleSize / 2 + 10
        circleY = height / 2
        rectX = width / 2 - rectSize - 10
        rectY = height / 2 - rectSize / 2
    }

    func draw() {
        updateHover()
        noStroke()
        if rectOver { background(0) }
        else if circleOver { background(255) }
        else { background(102) }
        stroke(255); fill(0)
        rect(rectX, rectY, rectSize, rectSize)
        stroke(0); fill(255)
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
}
