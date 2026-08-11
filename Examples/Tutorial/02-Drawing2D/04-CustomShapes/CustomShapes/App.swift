import metaphor

@main
final class CustomShapes: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Custom Shapes")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        strokeWeight(2)

        // 1. 頂点を並べて閉じる。外側と内側の角を交互に打つと星になる
        stroke(240)
        fill(230, 160, 60)
        beginShape()
        for i in 0..<10 {
            let radius: Float = (i % 2 == 0) ? 62 : 26
            let angle = Float(i) / 10 * TWO_PI - HALF_PI
            vertex(110 + cos(angle) * radius, 100 + sin(angle) * radius)
        }
        endShape(.close)

        // 2. bezierVertex は「直前の頂点から、2 つの制御点を経て、指定の点まで」
        //    曲線を伸ばす。つなげていくと曲線だけで輪郭を作れる
        fill(80, 170, 220)
        beginShape()
        vertex(320, 58)
        bezierVertex(370, 58, 386, 78, 386, 110)
        bezierVertex(386, 148, 350, 168, 320, 168)
        bezierVertex(276, 168, 254, 142, 254, 110)
        bezierVertex(254, 82, 284, 58, 320, 58)
        endShape(.close)

        // 3. bezier は 2 つの端点と 2 つの制御点で 1 本の曲線を引く
        noFill()
        stroke(240, 120, 180)
        strokeWeight(3)
        bezier(470, 150, 480, 40, 600, 160, 610, 50)

        // 4. beginContour で穴をあける。外周と逆回りに頂点を打つのが約束
        fill(120, 200, 160)
        stroke(240)
        strokeWeight(2)
        beginShape()
        vertex(40, 220)
        vertex(190, 220)
        vertex(190, 330)
        vertex(40, 330)
        beginContour()
        vertex(75, 250)
        vertex(75, 300)
        vertex(155, 300)
        vertex(155, 250)
        endContour()
        endShape(.close)

        // 5. beginShape はモードを取る。同じ頂点列でも解釈が変わる
        //    .lines は 2 頂点ずつを独立した線分として読む
        stroke(200, 200, 90)
        strokeWeight(4)
        noFill()
        beginShape(.lines)
        for k in 0..<8 {
            let x = 250 + Float(k) * 24
            vertex(x, 230)
            vertex(x + 16, 320)
        }
        endShape()

        // 同じ頂点列を .polygon（既定）で読むと、ひとつながりの折れ線になる
        stroke(120, 190, 240)
        beginShape()
        for k in 0..<8 {
            let x = 460 + Float(k) * 20
            vertex(x, 230)
            vertex(x + 12, 320)
        }
        endShape()
    }
}
