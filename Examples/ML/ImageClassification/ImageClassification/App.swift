// ImageClassification
//
// VNClassifyImageRequest を使ってプログラム的に生成した画像を分類し、
// 結果をテキストで表示するサンプル。
// MLTextureConverter で CGImage → MTLTexture → CVPixelBuffer の変換を行う。

import metaphor
import Vision

@main
final class ImageClassification: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Image Classification")
    }

    var converter: MLTextureConverter!
    var labels: [(String, Float)] = []

    func setup() {
        converter = createMLTextureConverter()
        classify()
    }

    func classify() {
        // テスト用の CGImage を生成（赤い円）
        let size = 299
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 40, y: 40, width: size - 80, height: size - 80))

        guard let cgImage = ctx.makeImage() else { return }

        // CGImage → MTLTexture → CVPixelBuffer
        guard let texture = converter.texture(from: cgImage),
              let pixelBuffer = converter.pixelBuffer(from: texture) else { return }

        // Vision で分類
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])

        if let results = request.results {
            labels = results
                .filter { $0.confidence > 0.01 }
                .prefix(8)
                .map { ($0.identifier, $0.confidence) }
        }
    }

    func draw() {
        background(Color(gray: 0.15))

        // 元画像を描画
        fill(Color(r: 0.2, g: 0.6, b: 0.1))
        noStroke()
        rect(50, 50, 200, 200)
        fill(Color(r: 1, g: 0.2, b: 0.1))
        circle(150, 150, 160)

        // 分類結果を表示
        fill(.white)
        textSize(18)
        text("Classification Results:", 300, 60)

        textSize(14)
        for (i, label) in labels.enumerated() {
            let y = Float(90 + i * 24)
            let pct = String(format: "%.1f%%", label.1 * 100)
            text("\(label.0): \(pct)", 300, y)
        }

        if labels.isEmpty {
            text("(no results)", 300, 90)
        }
    }
}
