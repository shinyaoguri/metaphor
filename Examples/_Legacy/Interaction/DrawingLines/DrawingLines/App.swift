import metaphor

@main
final class DrawingLines: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Drawing Lines")
    }

    func draw() {
        background(.black)

        if input.isMouseDown {
            let mx = input.mouseX
            let my = input.mouseY
            let px = input.pmouseX
            let py = input.pmouseY

            let dx = mx - px
            let dy = my - py
            let speed = sqrt(dx * dx + dy * dy)
            let weight = min(max(speed * 0.3, 1), 20)

            let hue = (mx / width).truncatingRemainder(dividingBy: 1.0)
            stroke(Color(hue: hue, saturation: 0.7, brightness: 1.0, alpha: 0.6))
            strokeWeight(weight)
            line(px, py, mx, my)
        }
    }
}
