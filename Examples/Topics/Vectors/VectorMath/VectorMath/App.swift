import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Topics/Vectors/VectorMath
// The original .pde is not bundled — see Examples/NOTICE.md.

// Vector Math
// Draw a vector from center to mouse, scaled to length 150 using Vec2's setMag().

@main
final class VectorMath: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Vector Math")
    }

    func draw() {
        background(0)

        // Vector pointing from the center to the mouse, scaled to length 150
        var mouse = Vec2(mouseX, mouseY) - Vec2(width / 2, height / 2)
        mouse.setMag(150)

        translate(width / 2, height / 2)
        stroke(255)
        strokeWeight(4)
        line(0, 0, mouse.x, mouse.y)
    }
}
