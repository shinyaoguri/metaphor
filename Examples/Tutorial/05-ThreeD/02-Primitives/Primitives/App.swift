import metaphor

@main
final class Primitives: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Primitives")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(18)
        lights()
        noStroke()

        // 上の段: 5 種類のプリミティブ。少し傾けると立体だと分かる
        fill(235, 180, 90)
        shape(centeredAt: 72, y: 105, label: "box(80)") { box(80) }
        shape(centeredAt: 196, y: 105, label: "sphere(45)") { sphere(45) }
        shape(centeredAt: 318, y: 105, label: "plane(90, 90)") { plane(90, 90) }
        shape(centeredAt: 437, y: 105, label: "cylinder(38, 84)") {
            cylinder(radius: 38, height: 84)
        }
        shape(centeredAt: 556, y: 105, label: "cone(40, 88)") {
            cone(radius: 40, height: 88)
        }

        // 下の段: トーラスと、同じ球を detail だけ変えたもの
        fill(110, 190, 200)
        shape(centeredAt: 80, y: 250, label: "torus(40, 16)") {
            torus(ringRadius: 40, tubeRadius: 16)
        }
        shape(centeredAt: 230, y: 250, label: "sphere detail: 4") { sphere(45, detail: 4) }
        shape(centeredAt: 380, y: 250, label: "detail: 8") { sphere(45, detail: 8) }
        shape(centeredAt: 535, y: 250, label: "detail: 24（既定）") { sphere(45, detail: 24) }
    }

    /// 1 つの形を、決まった傾きと中央揃えのラベル付きで置く。
    private func shape(centeredAt x: Float, y: Float, label: String, body: () -> Void) {
        push()
        translate(x, y, 0)
        rotateX(-0.5)
        rotateY(0.7)
        body()
        pop()

        pushStyle()
        fill(190)
        textSize(12)
        textAlign(.center)
        text(label, x, y + 78)
        popStyle()
    }
}
