import metaphor
import Foundation

@main
final class Clock: Sketch {
    var cx: Float = 0
    var cy: Float = 0
    var secondsRadius: Float = 0
    var minutesRadius: Float = 0
    var hoursRadius: Float = 0
    var clockDiameter: Float = 0
    var config: SketchConfig { SketchConfig(title: "Clock", width: 640, height: 360) }
    func setup() {
        stroke(255)
        let radius = min(width, height) / 2
        secondsRadius = radius * 0.72
        minutesRadius = radius * 0.60
        hoursRadius = radius * 0.50
        clockDiameter = radius * 1.8
        cx = width / 2
        cy = height / 2
    }
    func draw() {
        background(0)
        fill(80)
        noStroke()
        ellipse(cx, cy, clockDiameter, clockDiameter)
        let cal = Calendar.current
        let now = Date()
        let sec = Float(cal.component(.second, from: now))
        let min = Float(cal.component(.minute, from: now))
        let hr = Float(cal.component(.hour, from: now))
        let s = map(sec, 0, 60, 0, Float.pi * 2) - Float.pi / 2
        let m = map(min + norm(sec, 0, 60), 0, 60, 0, Float.pi * 2) - Float.pi / 2
        let h = map(hr + norm(min, 0, 60), 0, 24, 0, Float.pi * 4) - Float.pi / 2
        stroke(255)
        strokeWeight(1)
        line(cx, cy, cx + cos(s) * secondsRadius, cy + sin(s) * secondsRadius)
        strokeWeight(2)
        line(cx, cy, cx + cos(m) * minutesRadius, cy + sin(m) * minutesRadius)
        strokeWeight(4)
        line(cx, cy, cx + cos(h) * hoursRadius, cy + sin(h) * hoursRadius)
        strokeWeight(2)
        beginShape(.points)
        for a in stride(from: 0, to: 360, by: 6) {
            let angle = radians(Float(a))
            let x = cx + cos(angle) * secondsRadius
            let y = cy + sin(angle) * secondsRadius
            vertex(x, y)
        }
        endShape()
    }
}
