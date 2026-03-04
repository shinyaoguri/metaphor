import metaphor

@main
final class Explode: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Explode", width: 640, height: 360)
    }

    var img: MImage!
    let cellSize = 2
    var columns = 0
    var rows = 0

    func setup() {
        let imgW = Int(width) - 200
        let imgH = Int(height) - 100
        columns = imgW / cellSize
        rows = imgH / cellSize

        img = createImage(imgW, imgH)
        img.loadPixels()
        for y in 0..<imgH {
            for x in 0..<imgW {
                let idx = (y * imgW + x) * 4
                let nx = Float(x) / Float(imgW)
                let ny = Float(y) / Float(imgH)
                // Interesting pattern for brightness variation
                let v = sin(nx * 8) * cos(ny * 6) * 127 + 128
                let r = UInt8(max(0, min(255, Int(v * 0.8))))
                let g = UInt8(max(0, min(255, Int(v * 0.6 + ny * 80))))
                let b = UInt8(max(0, min(255, Int(v * 0.4 + nx * 100))))
                img.pixels[idx] = r; img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b; img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
    }

    func draw() {
        background(0)
        img.loadPixels()

        for i in 0..<columns {
            for j in 0..<rows {
                let x = i * cellSize + cellSize / 2
                let y = j * cellSize + cellSize / 2
                if x < img.width && y < img.height {
                    let loc = (y * img.width + x) * 4
                    let r = Float(img.pixels[loc])
                    let g = Float(img.pixels[loc + 1])
                    let b = Float(img.pixels[loc + 2])
                    let brightness = (r + g + b) / 3.0
                    let z = (mouseX / width) * brightness - 20

                    pushMatrix()
                    translate(Float(x) + 200, Float(y) + 100, z)
                    fill(r, g, b, 204)
                    noStroke()
                    rectMode(.center)
                    rect(0, 0, Float(cellSize), Float(cellSize))
                    popMatrix()
                }
            }
        }
    }
}
