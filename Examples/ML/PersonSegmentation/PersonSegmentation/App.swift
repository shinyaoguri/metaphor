// PersonSegmentation
//
// カメラ映像に対して VNGeneratePersonSegmentationRequest を実行し、
// 人物マスクをテクスチャとしてオーバーレイ表示するサンプル。
// Vision のマスク出力は単チャネル (OneComponent8) なので、
// CIImage 経由で CGImage に変換してから MLTextureConverter に渡す。
//
// 初回実行時は macOS がカメラ権限を要求する。swift run バイナリでの
// ダイアログの仕組み・拒否後の復旧手順はリポジトリ直下の
// docs/permissions.md を参照。

import metaphor
import Vision
import CoreImage

@main
final class PersonSegmentation: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "Person Segmentation")
    }

    var capture: CaptureDevice?
    var converter: MLTextureConverter!
    var maskImage: MImage?
    let ciContext = CIContext()

    func setup() {
        capture = createCapture(width: 1280, height: 720, position: .front)
        converter = createMLTextureConverter()
    }

    func draw() {
        background(.black)

        // createCapture() は非 Optional を返すので、カメラの有無は isAvailable で見る。
        guard let cam = capture, cam.isAvailable else {
            fill(.white)
            textSize(20)
            text("Camera not available", 50, height / 2)
            return
        }

        // カメラ映像を表示
        image(cam, 0, 0, width, height)

        // セグメンテーション実行
        if let texture = cam.texture,
           let pixelBuffer = converter.pixelBuffer(from: texture) {
            segment(pixelBuffer: pixelBuffer)
        }

        // マスクを半透明オーバーレイ
        if let mask = maskImage {
            tint(Color(r: 0, g: 1, b: 0.5, a: 0.5))
            image(mask, 0, 0, width, height)
            noTint()
        }
    }

    func segment(pixelBuffer: CVPixelBuffer) {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])

        guard let result = request.results?.first else { return }

        // マスクは OneComponent8 (単チャネル) なので BGRA の CVPixelBuffer ではない。
        // CIImage → CGImage に変換してから MLTextureConverter でテクスチャ化する。
        let ciImage = CIImage(cvPixelBuffer: result.pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent),
              let maskTexture = converter.texture(from: cgImage) else { return }
        maskImage = MImage(texture: maskTexture)
    }
}
