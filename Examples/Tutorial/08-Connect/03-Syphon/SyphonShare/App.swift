import metaphor
import MetaphorSyphon  // Syphon 出力は別パッケージ。import するだけで出力の実装が登録される

@main
final class SyphonShare: Sketch {
    /// 受け側のアプリ（MadMapper・Resolume・Simple Client など）の一覧に出る名前
    let syphonServerName = "metaphor-tutorial"

    var config: SketchConfig {
        SketchConfig(
            width: 1280,  // 送り出す解像度。受け側にはこの大きさで届く
            height: 720,
            title: "Syphon Share",
            windowScale: 0.5,  // 手元の窓だけ半分。送る絵は 1280x720 のまま
            // plugins に .syphon(name:) を書いた時点で Syphon 出力が有効になる。
            // 名前を省略した .syphon() なら title（"Syphon Share"）で出る
            plugins: [.syphon(name: syphonServerName)]
        )
    }

    let ringCount = 5

    func draw() {
        background(10, 12, 18)

        let t = Float(frameCount) * 0.01
        push()
        translate(width / 2, height / 2)

        // 送り出す素材そのもの。描き方は 2D の章までと何も変わらない
        noFill()
        for ring in 0..<ringCount {
            let ringF = Float(ring)
            let radius = 90 + ringF * 55
            stroke(Color(r: 0.3 + ringF * 0.12, g: 0.7, b: 1, alpha: 0.9 - ringF * 0.12))
            strokeWeight(4)
            let sweep = PI + sin(t + ringF * 0.7) * PI * 0.6
            arc(0, 0, radius * 2, radius * 2, t * (ringF + 1) * 0.3, t * (ringF + 1) * 0.3 + sweep)
        }

        noStroke()
        fill(Color(r: 1, g: 0.9, b: 0.5))
        circle(0, 0, 60)
        pop()

        drawOverlay()
    }

    /// 受け側で名前と解像度を確かめられるよう、絵に焼き込んでおく
    private func drawOverlay() {
        noStroke()
        fill(Color(gray: 0, alpha: 0.55))
        rect(0, height - 92, width, 92)

        fill(Color(gray: 0.95))
        textSize(22)
        textAlign(.left, .top)
        text("Syphon サーバー名: \(syphonServerName)", 32, height - 78)

        fill(Color(gray: 0.7))
        textSize(17)
        text("\(Int(width)) x \(Int(height))  /  手元の窓はその \(config.windowScale) 倍", 32, height - 44)

        // 受け側で切れていないかを確かめるための隅の目印
        stroke(Color(gray: 0.5))
        strokeWeight(3)
        noFill()
        rect(8, 8, width - 16, height - 16)
    }
}
