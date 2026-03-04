import metaphor

@main
final class Extrusion: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Extrusion")
    }

    var values: [[Int]] = []
    var imgW = 0
    var imgH = 0
    var angle: Float = 0

    func setup() {
        noFill()
        imgW = 200
        imgH = 150

        guard let img = createImage(imgW, imgH) else { return }
        img.loadPixels()
        values = Array(repeating: Array(repeating: 0, count: imgH), count: imgW)

        for y in 0..<imgH {
            for x in 0..<imgW {
                let idx = (y * imgW + x) * 4
                let nx = Float(x) / Float(imgW)
                let ny = Float(y) / Float(imgH)
                let v = sin(nx * 10) * cos(ny * 8) * 100 + 100
                let b = UInt8(max(0, min(255, Int(v))))
                img.pixels[idx] = b; img.pixels[idx + 1] = b
                img.pixels[idx + 2] = b; img.pixels[idx + 3] = 255
                values[x][y] = Int(b)
            }
        }
        img.updatePixels()
    }

    func draw() {
        background(0)
        translate(width / 2, height / 2, -Float(height) / 2)
        scale(2.0)

        angle += 0.005
        rotateY(angle)

        for i in stride(from: 0, to: imgH, by: 4) {
            for j in stride(from: 0, to: imgW, by: 4) {
                let v = values[j][i]
                stroke(Float(v), 255)
                let xp = Float(j) - Float(imgW) / 2
                let yp = Float(i) - Float(imgH) / 2
                beginShape3D(.lines)
                vertex(xp, yp, Float(-v)); vertex(xp, yp, Float(-v) - 10)
                endShape3D()
            }
        }
    }
}
