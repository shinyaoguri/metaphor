import metaphor

@main
final class VectorMath: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Vector Math", width: 640, height: 360)
    }

    func draw() {
        background(0)
        var mx = mouseX - width / 2
        var my = mouseY - height / 2
        let mag = sqrt(mx * mx + my * my)
        if mag > 0 {
            mx = mx / mag * 150
            my = my / mag * 150
        }
        translate(width / 2, height / 2)
        stroke(255)
        strokeWeight(4)
        line(0, 0, mx, my)
    }
}
