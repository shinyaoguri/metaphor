import metaphor

@main
final class PostProcess: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PostProcess")
    }

    // 48 フレームごとに 4 通りの重ねがけを切り替える
    let phaseLength = 48

    func setup() {
        noStroke()
    }

    func draw() {
        let phase = (frameCount / phaseLength) % 4

        // エフェクトは毎フレーム丸ごと差し替える（追加ではなく置き換え）
        switch phase {
        case 0:
            setPostEffects([])
        case 1:
            setPostEffects([BloomEffect(intensity: 2.2, threshold: 0.45)])
        case 2:
            setPostEffects([
                BloomEffect(intensity: 2.2, threshold: 0.45),
                VignetteEffect(intensity: 0.4, smoothness: 0.35),
            ])
        default:
            setPostEffects([GrayscaleEffect()])
        }

        background(10, 12, 22)

        // 光の点を円周に並べて回す。明るいところだけ Bloom がにじむ
        let t = Float(frameCount) * 0.02
        for i in 0..<12 {
            let a = t + Float(i) / 12 * TWO_PI
            let x = 320 + cos(a) * 120
            let y = 180 + sin(a) * 90
            fill(255, 210, 120)
            circle(x, y, 14)
            fill(70, 80, 110)                     // 暗い点は Bloom のしきい値に届かない
            circle(320 - cos(a) * 60, 180 - sin(a) * 45, 10)
        }

        fill(255, 255, 255)
        circle(320, 180, 26)

        fill(235)
        textSize(14)
        textAlign(.center)
        text(label(for: phase), 320, 330)
    }

    func label(for phase: Int) -> String {
        switch phase {
        case 0: return "エフェクト無し"
        case 1: return "Bloom"
        case 2: return "Bloom + Vignette"
        default: return "Grayscale（文字も一緒に灰色になる）"
        }
    }
}
