import metaphor

@main
final class Mandelbrot: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Mandelbrot", width: 640, height: 360)
    }

    var img: MImage!

    func setup() {
        noLoop()
        img = createImage(Int(width), Int(height))

        let w: Float = 4
        let h: Float = (w * height) / width
        let xmin = -w / 2
        let ymin = -h / 2
        let xmax = xmin + w
        let ymax = ymin + h
        let dx = (xmax - xmin) / width
        let dy = (ymax - ymin) / height
        let maxIterations = 100

        img.loadPixels()
        var cy = ymin
        for j in 0..<Int(height) {
            var cx = xmin
            for i in 0..<Int(width) {
                var a = cx
                var b = cy
                var n = 0
                let maxVal: Float = 4.0
                var absOld: Float = 0
                var convergeNumber = Float(maxIterations)

                while n < maxIterations {
                    let aa = a * a
                    let bb = b * b
                    let absVal = sqrt(aa + bb)
                    if absVal > maxVal {
                        let diffToLast = absVal - absOld
                        let diffToMax = maxVal - absOld
                        convergeNumber = Float(n) + diffToMax / diffToLast
                        break
                    }
                    let twoab = 2.0 * a * b
                    a = aa - bb + cx
                    b = twoab + cy
                    n += 1
                    absOld = absVal
                }

                let idx = (j * Int(width) + i) * 4
                if n == maxIterations {
                    img.pixels[idx] = 0
                    img.pixels[idx + 1] = 0
                    img.pixels[idx + 2] = 0
                    img.pixels[idx + 3] = 255
                } else {
                    let norm = convergeNumber / Float(maxIterations)
                    let brightness = UInt8(sqrt(norm) * 255)
                    img.pixels[idx] = brightness
                    img.pixels[idx + 1] = brightness
                    img.pixels[idx + 2] = brightness
                    img.pixels[idx + 3] = 255
                }
                cx += dx
            }
            cy += dy
        }
        img.updatePixels()
    }

    func draw() {
        background(255)
        image(img, 0, 0)
    }
}
