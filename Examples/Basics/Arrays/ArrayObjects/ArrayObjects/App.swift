import metaphor

class Module {
    var xOffset: Float; var yOffset: Float; var x: Float; var y: Float
    var unit: Float; var xDirection: Float = 1; var yDirection: Float = 1; var speed: Float
    init(_ xo: Float, _ yo: Float, _ x: Float, _ y: Float, _ sp: Float, _ u: Float) {
        xOffset = xo; yOffset = yo; self.x = x; self.y = y; speed = sp; unit = u
    }
    func update() {
        x += speed * xDirection
        if x >= unit || x <= 0 { xDirection *= -1; x += xDirection; y += yDirection }
        if y >= unit || y <= 0 { yDirection *= -1; y += yDirection }
    }
}

@main
final class ArrayObjects: Sketch {
    var mods: [Module] = []
    let unit: Float = 40
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Array Objects") }
    func setup() {
        noStroke()
        let wideCount = Int(width / unit); let highCount = Int(height / unit)
        for y in 0..<highCount {
            for x in 0..<wideCount {
                mods.append(Module(Float(x) * unit, Float(y) * unit, unit / 2, unit / 2, random(0.05, 0.8), unit))
            }
        }
    }
    func draw() {
        background(0); fill(255)
        for mod in mods {
            mod.update()
            ellipse(mod.xOffset + mod.x, mod.yOffset + mod.y, 6, 6)
        }
    }
}
