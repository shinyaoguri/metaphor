import metaphor
import Foundation

@main
final class Rotate: Sketch {
    var angle: Float = 0
    var jitter: Float = 0
    var config: SketchConfig { SketchConfig(title: "Rotate", width: 640, height: 360) }
    func setup() {
        noStroke()
        fill(255)
        rectMode(.center)
    }
    func draw() {
        background(51)
        let sec = Calendar.current.component(.second, from: Date())
        if sec % 2 == 0 {
            jitter = random(-0.1, 0.1)
        }
        angle += jitter
        let c = cos(angle)
        translate(width / 2, height / 2)
        rotate(c)
        rect(0, 0, 180, 180)
    }
}
