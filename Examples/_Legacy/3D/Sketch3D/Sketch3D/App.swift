import metaphor

@main
final class Sketch3D: Sketch {
    var config: SketchConfig {
        SketchConfig(
            title: "Sketch3D",
            syphonName: "Sketch3D"
        )
    }

    func draw() {
        background(.black)

        let t = time

        // ライティング
        lights()

        // 中央の回転キューブ
        pushMatrix()
        rotateY(t * 0.5)
        rotateX(t * 0.35)
        fill(Color(r: 1, g: 0.3, b: 0.3))
        box(200)
        popMatrix()

        // 周回する球体
        let orbitRadius: Float = 400
        for i in 0..<6 {
            let angle = Float(i) / 6.0 * Float.pi * 2 + t * 0.4
            let x = cos(angle) * orbitRadius
            let z = sin(angle) * orbitRadius

            let hue = (Float(i) / 6.0 + t * 0.05)
                .truncatingRemainder(dividingBy: 1.0)

            pushMatrix()
            translate(x, 0, z)
            rotateY(t * 2)
            fill(Color(hue: hue, saturation: 0.8, brightness: 1.0))
            sphere(60)
            popMatrix()
        }

        // 底面のプレーン
        pushMatrix()
        translate(0, -200, 0)
        rotateX(-Float.pi / 2)
        fill(Color(gray: 0.3))
        plane(1000, 1000)
        popMatrix()

        // シリンダーとコーン
        pushMatrix()
        translate(-500, -100, 0)
        fill(Color(r: 0.3, g: 0.8, b: 0.3))
        cylinder(radius: 50, height: 200)
        popMatrix()

        pushMatrix()
        translate(500, -100, 0)
        fill(Color(r: 0.3, g: 0.3, b: 0.8))
        cone(radius: 80, height: 200)
        popMatrix()

        // トーラス
        pushMatrix()
        translate(0, 200, -300)
        rotateX(t * 0.6)
        rotateZ(t * 0.3)
        fill(Color(hue: t * 0.1, saturation: 0.6, brightness: 1.0))
        torus(ringRadius: 120, tubeRadius: 40)
        popMatrix()

        // 2Dオーバーレイ
        noStroke()
        fill(.white)
        circle(width - 40, 40, 16)
    }

    func mousePressed() {
        print("click: \(input.mouseX), \(input.mouseY)")
    }
}
