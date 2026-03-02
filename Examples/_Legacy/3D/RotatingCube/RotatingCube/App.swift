import metaphor

@main
final class RotatingCube: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Rotating Cube", syphonName: "RotatingCube")
    }

    func draw() {
        background(Color(gray: 0.05))

        lights()
        directionalLight(1, 1, 1)
        ambientLight(0.3)

        // 回転するキューブ
        pushMatrix()
        rotateY(time * 0.5)
        rotateX(time * 0.35)

        let hue = (time * 0.05).truncatingRemainder(dividingBy: 1.0)
        fill(Color(hue: hue, saturation: 0.8, brightness: 1.0))
        box(200)
        popMatrix()

        // 床面
        pushMatrix()
        translate(0, -200, 0)
        rotateX(-Float.pi / 2)
        fill(Color(gray: 0.15))
        plane(600, 600)
        popMatrix()
    }
}
