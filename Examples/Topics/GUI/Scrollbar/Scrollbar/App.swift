import metaphor

struct HScrollbar {
    var xpos: Float, ypos: Float
    var swidth: Float, sheight: Float
    var spos: Float, newspos: Float
    var sposMin: Float, sposMax: Float
    var loose: Float
    var over = false, locked = false
    var ratio: Float

    init(_ xp: Float, _ yp: Float, _ sw: Float, _ sh: Float, _ l: Float) {
        swidth = sw; sheight = sh; loose = l
        ratio = sw / (sw - sh)
        xpos = xp; ypos = yp - sh / 2
        spos = xp + sw / 2 - sh / 2
        newspos = spos
        sposMin = xp; sposMax = xp + sw - sh
    }

    mutating func update(_ mx: Float, _ my: Float, _ pressed: Bool, _ firstPress: Bool) {
        over = mx > xpos && mx < xpos + swidth && my > ypos && my < ypos + sheight
        if firstPress && over { locked = true }
        if !pressed { locked = false }
        if locked { newspos = max(sposMin, min(mx - sheight / 2, sposMax)) }
        if abs(newspos - spos) > 1 { spos += (newspos - spos) / loose }
    }

    func getPos() -> Float { spos * ratio }
}

@main
final class Scrollbar: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Scrollbar") }

    var hs1: HScrollbar?
    var hs2: HScrollbar?
    var firstPress = false

    func setup() {
        noStroke()
        hs1 = HScrollbar(0, height / 2 - 8, width, 16, 16)
        hs2 = HScrollbar(0, height / 2 + 8, width, 16, 16)
    }

    func draw() {
        background(255)
        guard var h1 = hs1, var h2 = hs2 else { return }
        h1.update(mouseX, mouseY, isMousePressed, firstPress)
        h2.update(mouseX, mouseY, isMousePressed, firstPress)
        hs1 = h1; hs2 = h2

        // Draw colored regions based on scrollbar position
        let pos1 = h1.getPos() - width / 2
        fill(255, 100, 100)
        rect(width / 2 + pos1 * 1.5 - 50, 20, 100, height / 2 - 40)

        let pos2 = h2.getPos() - width / 2
        fill(100, 100, 255)
        rect(width / 2 + pos2 * 1.5 - 50, height / 2 + 20, 100, height / 2 - 40)

        // Draw scrollbars
        noStroke(); fill(204)
        rect(h1.xpos, h1.ypos, h1.swidth, h1.sheight)
        fill(h1.over || h1.locked ? 0 : 102)
        rect(h1.spos, h1.ypos, h1.sheight, h1.sheight)
        fill(204)
        rect(h2.xpos, h2.ypos, h2.swidth, h2.sheight)
        fill(h2.over || h2.locked ? 0 : 102)
        rect(h2.spos, h2.ypos, h2.sheight, h2.sheight)

        stroke(0)
        line(0, height / 2, width, height / 2)
        if firstPress { firstPress = false }
    }

    func mousePressed() { firstPress = true }
}
