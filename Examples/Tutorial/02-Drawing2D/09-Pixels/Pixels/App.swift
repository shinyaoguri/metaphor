import metaphor

@main
final class Pixels: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Pixels")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        // まず普通に描く
        background(24)
        noStroke()
        for i in 0..<9 {
            fill(60 + Float(i) * 20, 200 - Float(i) * 15, 240 - Float(i) * 10)
            circle(70 + Float(i) * 62, height * 0.5, 130)
        }

        // ここまでの描画結果を CPU 側の配列へ読み戻す
        loadPixels()

        // pixels は 1 次元。x, y からの添字は y * 幅 + x
        let w = Int(width)
        let h = Int(height)
        for y in 0..<h {
            for x in w / 2..<w {
                let index = y * w + x
                let packed = pixels[index]

                // 1 画素は BGRA パックの UInt32。取り出してから加工する
                let r = Float((packed >> 16) & 0xFF)
                let g = Float((packed >> 8) & 0xFF)
                let b = Float(packed & 0xFF)

                // 右半分だけ輝度に落とす（人間の目の感度に合わせた重み付け）
                let luma = 0.299 * r + 0.587 * g + 0.114 * b
                pixels[index] = color(luma, luma, luma)
            }
        }

        // 書き換えた配列を画面へ戻す。これを忘れると何も変わらない
        updatePixels()

        // updatePixels() のあとは通常の描画に戻れる
        stroke(255)
        strokeWeight(2)
        line(width * 0.5, 0, width * 0.5, height)
    }
}
