import metaphor

@main
final class WaveGradient: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Wave Gradient") }
    func setup() {
        noLoop()
    }
    func draw() {
        background(200)

        guard let gradient = createImage(Int(width), Int(height)) else { return }
        gradient.loadPixels()

        let amplitude: Float = 30
        let fillGap = 2
        var frequency: Float = 0
        let w = Int(width)
        let h = Int(height)

        for i in -75..<(h + 75) {
            var angle: Float = 0
            frequency += 0.002
            for j in 0..<(w + 75) {
                let py = Float(i) + sin(radians(angle)) * amplitude
                angle += frequency
                let r = UInt8(clamping: Int(abs(py - Float(i)) * 255 / amplitude))
                let g = UInt8(clamping: Int(255 - abs(py - Float(i)) * 255 / amplitude))
                let b = UInt8(clamping: Int(Float(j) * (255.0 / (Float(w) + 50))))
                for filler in 0..<fillGap {
                    setPixel(&gradient.pixels, w, h, j - filler, Int(py) - filler, r, g, b)
                    setPixel(&gradient.pixels, w, h, j, Int(py), r, g, b)
                    setPixel(&gradient.pixels, w, h, j + filler, Int(py) + filler, r, g, b)
                }
            }
        }

        gradient.updatePixels()
        image(gradient, 0, 0)
    }

    private func setPixel(_ pixels: inout [UInt8], _ w: Int, _ h: Int,
                           _ x: Int, _ y: Int,
                           _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        guard x >= 0, x < w, y >= 0, y < h else { return }
        let idx = (y * w + x) * 4
        pixels[idx] = r
        pixels[idx + 1] = g
        pixels[idx + 2] = b
        pixels[idx + 3] = 255
    }
}
