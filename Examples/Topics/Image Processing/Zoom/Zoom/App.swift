import metaphor

@main
final class Zoom: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Zoom", width: 640, height: 360)
    }

    var imgPixels: [[UInt32]] = []
    var imgW = 0
    var imgH = 0
    var sval: Float = 1.0
    var nmx: Float = 0
    var nmy: Float = 0
    let res = 5

    func setup() {
        noFill()
        stroke(255)

        imgW = 200
        imgH = 150
        let img = createImage(imgW, imgH)
        img.loadPixels()
        imgPixels = Array(repeating: Array(repeating: 0, count: imgH), count: imgW)

        for y in 0..<imgH {
            for x in 0..<imgW {
                let idx = (y * imgW + x) * 4
                let nx = Float(x) / Float(imgW)
                let ny = Float(y) / Float(imgH)
                let r = UInt8(max(0, min(255, Int(sin(ny * .pi * 2) * 80 + 100))))
                let g = UInt8(max(0, min(255, Int(cos(nx * .pi * 3) * 60 + 120))))
                let b = UInt8(max(0, min(255, Int(sin(nx * 10 + ny * 8) * 50 + 100))))
                img.pixels[idx] = r; img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b; img.pixels[idx + 3] = 255
                // Pack RGB into UInt32 for easy access
                imgPixels[x][y] = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
            }
        }
        img.updatePixels()
    }

    func draw() {
        background(0)

        nmx += (mouseX - nmx) / 20
        nmy += (mouseY - nmy) / 20

        if isMousePressed {
            sval += 0.005
        } else {
            sval -= 0.01
        }
        sval = constrain(sval, 1.0, 2.0)

        translate(width / 2 + nmx * sval - 100, height / 2 + nmy * sval - 100, -50)
        scale(sval)
        rotateZ(.pi / 9 - sval + 1.0)
        rotateX(.pi / sval / 8 - 0.125)
        rotateY(sval / 8 - 0.125)
        translate(-width / 2, -height / 2, 0)

        for i in stride(from: 0, to: imgH, by: res) {
            for j in stride(from: 0, to: imgW, by: res) {
                let packed = imgPixels[j][i]
                let rr = Float((packed >> 16) & 0xFF)
                let gg = Float((packed >> 8) & 0xFF)
                let bb = Float(packed & 0xFF)
                let tt = rr + gg + bb
                stroke(rr, gg, bb)
                line(Float(i), Float(j), tt / 10 - 20, Float(i), Float(j), tt / 10)
            }
        }
    }
}
