import metaphor

// Vector Math
// 中心からマウスへ向かうベクトルを Vec2 の setMag() で長さ 150 にそろえて描く例。

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
