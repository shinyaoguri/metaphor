import metaphor

class MRect {
    var w: Float; var xpos: Float; var h: Float; var ypos: Float; var d: Float; var t: Float
    init(_ iw: Float, _ ixp: Float, _ ih: Float, _ iyp: Float, _ id: Float, _ it: Float) {
        w = iw; xpos = ixp; h = ih; ypos = iyp; d = id; t = it
    }
    func move(_ posX: Float, _ posY: Float, _ damping: Float) {
        var dif = ypos - posY
        if abs(dif) > 1 { ypos -= dif / damping }
        dif = xpos - posX
        if abs(dif) > 1 { xpos -= dif / damping }
    }
}

@main
final class Objects: Sketch {
    var r1: MRect!; var r2: MRect!; var r3: MRect!; var r4: MRect!
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Objects") }
    func setup() {
        fill(255, 204); noStroke()
        r1 = MRect(1, 134, 0.532, 0.1 * height, 10, 60)
        r2 = MRect(2, 44, 0.166, 0.3 * height, 5, 50)
        r3 = MRect(2, 58, 0.332, 0.4 * height, 10, 35)
        r4 = MRect(1, 120, 0.0498, 0.9 * height, 15, 60)
    }
    func draw() {
        background(0)
        for r in [r1!, r2!, r3!, r4!] {
            for i in 0..<Int(r.t) {
                rect(r.xpos + Float(i) * (r.d + r.w), r.ypos, r.w, height * r.h)
            }
        }
        r1.move(mouseX - width / 2, mouseY + height * 0.1, 30)
        r2.move(Float(Int(mouseX + width * 0.05) % Int(width)), mouseY + height * 0.025, 20)
        r3.move(mouseX / 4, mouseY - height * 0.025, 40)
        r4.move(mouseX - width / 2, height - mouseY, 50)
    }
}
