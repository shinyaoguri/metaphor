import metaphor

@main
final class Constrain: Sketch {
    var mx: Float = 0
    var my: Float = 0
    let easing: Float = 0.05
    let radius: Float = 24
    let edge: Float = 100
    var config: SketchConfig { SketchConfig(title: "Constrain", width: 640, height: 360) }
    func setup() {
        noStroke()
        ellipseMode(.radius)
        rectMode(.corners)
    }
    func draw() {
        background(51)
        let inner = edge + radius
        if abs(mouseX - mx) > 0.1 { mx = mx + (mouseX - mx) * easing }
        if abs(mouseY - my) > 0.1 { my = my + (mouseY - my) * easing }
        mx = constrain(mx, inner, width - inner)
        my = constrain(my, inner, height - inner)
        fill(76)
        rect(edge, edge, width - edge, height - edge)
        fill(255)
        ellipse(mx, my, radius, radius)
    }
}
