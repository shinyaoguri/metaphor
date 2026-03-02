import metaphor
import Foundation

/// MPS (Metal Performance Shaders) リアルタイムデモ
///
/// 毎フレーム MPS フィルタをアニメーション付きで適用。
/// Gaussian Blur の sigma が時間で変化し、MPSのリアルタイム性能を体感できる。
@main
final class MPSShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1024,
            height: 640,
            title: "MPS Showcase",
            windowScale: 1.0
        )
    }

    var mps: MPSImageFilterWrapper!
    var imgW = 256
    var imgH = 256

    func setup() {
        mps = createMPSFilter()
    }

    func draw() {
        background(Color(gray: 0.06))

        let t = Float(frameCount) * 0.03
        let size: Float = 280
        let gap: Float = 20
        let totalW = size * 3 + gap * 2
        let startX = (width - totalW) / 2
        let y: Float = 130

        // Regenerate source with moving circles
        let source = generateTestImage(time: t)

        // --- Animated Gaussian Blur ---
        let sigma = abs(sin(t)) * 20 + 0.5
        let blurred = MImage(texture: source.texture)
        mps.gaussianBlur(blurred, sigma: sigma)

        // --- Animated Threshold ---
        let thresh = (sin(t * 0.7) * 0.5 + 0.5)
        let threshed = MImage(texture: source.texture)
        mps.threshold(threshed, value: thresh)

        // --- Sobel ---
        let sobeled = MImage(texture: source.texture)
        mps.sobel(sobeled)

        // Draw tiles
        drawTile(blurred, x: startX, y: y, size: size,
                 label: "Gaussian Blur",
                 value: String(format: "σ = %.1f", sigma),
                 hue: 0.55)

        drawTile(threshed, x: startX + size + gap, y: y, size: size,
                 label: "Threshold",
                 value: String(format: "t = %.2f", thresh),
                 hue: 0.08)

        drawTile(sobeled, x: startX + (size + gap) * 2, y: y, size: size,
                 label: "Sobel Edge",
                 value: "realtime",
                 hue: 0.33)

        // Title
        fill(.white)
        textSize(22)
        text("Metal Performance Shaders", 30, 42)

        fill(Color(gray: 0.45))
        textSize(12)
        text("3 MPS filters applied every frame on GPU", 30, 66)

        // Sigma bar visualization
        let barX: Float = 30
        let barY: Float = 90
        let barW: Float = 300
        let barH: Float = 6
        noStroke()
        fill(Color(gray: 0.15))
        rect(barX, barY, barW, barH, 3)
        fill(Color(hue: 0.55, saturation: 0.7, brightness: 0.9))
        rect(barX, barY, barW * (sigma / 20.5), barH, 3)

        fill(Color(gray: 0.4))
        textSize(10)
        text("blur σ", barX + barW + 8, barY + 6)

        // Frame counter
        fill(Color(gray: 0.25))
        textSize(10)
        text("frame: \(frameCount)", width - 100, height - 14)
    }

    func drawTile(_ img: MImage, x: Float, y: Float, size: Float,
                  label: String, value: String, hue: Float) {
        image(img, x, y, size, size)

        // Border
        noFill()
        stroke(Color(hue: hue, saturation: 0.5, brightness: 0.4))
        strokeWeight(1)
        rect(x, y, size, size)

        // Label
        fill(Color(hue: hue, saturation: 0.7, brightness: 1))
        noStroke()
        textSize(13)
        text(label, x, y - 18)

        // Value badge
        fill(Color(hue: hue, saturation: 0.4, brightness: 0.15))
        rect(x, y + size + 6, Float(value.count) * 8 + 12, 20, 4)
        fill(Color(hue: hue, saturation: 0.6, brightness: 0.9))
        textSize(11)
        text(value, x + 6, y + size + 20)
    }

    // MARK: - Test Image

    func generateTestImage(time t: Float) -> MImage {
        let w = imgW
        let h = imgH
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        // Animated circle positions
        let c1x = 0.5 + sin(t * 1.0) * 0.25
        let c1y = 0.5 + cos(t * 0.8) * 0.25
        let c2x = 0.3 + sin(t * 1.3 + 2.0) * 0.2
        let c2y = 0.3 + cos(t * 1.1 + 1.0) * 0.2
        let c3x = 0.7 + sin(t * 0.7 + 4.0) * 0.2
        let c3y = 0.7 + cos(t * 0.9 + 3.0) * 0.2

        for py in 0..<h {
            for px in 0..<w {
                let i = (py * w + px) * 4
                let u = Float(px) / Float(w)
                let v = Float(py) / Float(h)

                // Dark gradient background
                var r: Float = u * 0.15 + 0.02
                var g: Float = v * 0.1 + 0.02
                var b: Float = (1 - u) * 0.2 + 0.02

                // Circle 1: warm orange, big
                let d1 = sqrt((u - c1x) * (u - c1x) + (v - c1y) * (v - c1y))
                if d1 < 0.2 {
                    let f = (1 - d1 / 0.2) * 0.9
                    r += (1.0 - r) * f; g += (0.6 - g) * f; b += (0.1 - b) * f
                }

                // Circle 2: cyan, medium
                let d2 = sqrt((u - c2x) * (u - c2x) + (v - c2y) * (v - c2y))
                if d2 < 0.14 {
                    let f = (1 - d2 / 0.14) * 0.85
                    r += (0.1 - r) * f; g += (0.8 - g) * f; b += (1.0 - b) * f
                }

                // Circle 3: magenta, medium
                let d3 = sqrt((u - c3x) * (u - c3x) + (v - c3y) * (v - c3y))
                if d3 < 0.15 {
                    let f = (1 - d3 / 0.15) * 0.85
                    r += (0.9 - r) * f; g += (0.2 - g) * f; b += (0.8 - b) * f
                }

                pixels[i]     = UInt8(min(255, b * 255))
                pixels[i + 1] = UInt8(min(255, g * 255))
                pixels[i + 2] = UInt8(min(255, r * 255))
                pixels[i + 3] = 255
            }
        }

        guard let img = createImage(w, h) else {
            fatalError("Failed to create test image")
        }
        img.loadPixels()
        img.pixels = pixels
        img.updatePixels()
        return img
    }
}
