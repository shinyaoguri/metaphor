// StyleTransfer
//
// CoreML のスタイル変換モデルを使って描画結果をリアルタイム変換するサンプル。
// MLTextureConverter で MTLTexture ↔ CVPixelBuffer を変換し、
// CoreML モデルの入出力に使用する。
//
// 使い方:
//   1. Apple の Style Transfer モデル等の .mlmodel をプロジェクトに追加
//      https://developer.apple.com/machine-learning/models/
//   2. 下記の "YourStyleTransfer" を実際のモデルクラス名に変更
//   3. swift build && swift run

import metaphor
import CoreML
import Vision

@main
final class StyleTransfer: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Style Transfer")
    }

    var converter: MLTextureConverter!
    var model: VNCoreMLModel?
    var styledImage: MImage?
    var angle: Float = 0

    func setup() {
        converter = createMLTextureConverter()

        // モデルの読み込み（パスは実際の .mlmodelc に合わせて変更）
        // let config = MLModelConfiguration()
        // if let mlModel = try? YourStyleTransfer(configuration: config) {
        //     model = try? VNCoreMLModel(for: mlModel.model)
        // }
    }

    func draw() {
        // 元の描画
        background(Color(r: 0.1, g: 0.1, b: 0.2))
        noStroke()
        angle += 0.02

        for i in 0..<6 {
            let a = angle + Float(i) * Float.pi / 3
            let x = width / 2 + cos(a) * 150
            let y = height / 2 + sin(a) * 150
            let hue = Float(i) / 6.0
            fill(Color(hue: hue, saturation: 0.8, brightness: 1.0))
            circle(x, y, 80)
        }

        fill(.white)
        circle(width / 2, height / 2, 60)

        // モデルが読み込まれている場合、スタイル変換を適用
        if let model = model {
            applyStyle(model: model)
        }

        // スタイル変換結果を表示
        if let styled = styledImage {
            image(styled, 0, 0, width, height)
        }

        fill(.white)
        textSize(14)
        if model == nil {
            text("Model not loaded - see source for setup instructions", 20, height - 30)
        }
    }

    func applyStyle(model: VNCoreMLModel) {
        // 現在の描画内容を CGImage として取得し、CVPixelBuffer に変換
        let size = 512
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ),
        let cgImage = ctx.makeImage(),
        let texture = converter.texture(from: cgImage),
        let pixelBuffer = converter.pixelBuffer(from: texture) else { return }

        // Vision 経由で CoreML モデルを実行
        let request = VNCoreMLRequest(model: model) { [weak self] request, _ in
            guard let result = request.results?.first as? VNPixelBufferObservation,
                  let self = self else { return }
            // 出力 CVPixelBuffer → MTLTexture → MImage
            if let outTexture = self.converter.texture(from: result.pixelBuffer) {
                self.styledImage = MImage(texture: outTexture)
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
}
