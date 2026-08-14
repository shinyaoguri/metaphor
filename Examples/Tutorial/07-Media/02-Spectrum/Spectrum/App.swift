import metaphor

@main
final class Spectrum: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Spectrum")
    }

    var audio: AudioAnalyzer?
    var message = ""

    // 画面に描くバーの本数。FFT の分解能そのものではなく、見せたい粗さで決める
    let bars = 64

    // ビートを検出した瞬間から減っていく値。0 になるまで背景を明るくする
    var flash: Float = 0

    func setup() {
        let input = createAudioInput(fftSize: 2048)
        // 既定の 0.8 だとバーがなめらかすぎるので、少し反応を速くする
        input.smoothing = 0.6
        do {
            try input.start()
            audio = input
        } catch {
            message = "マイクを開けませんでした: \(error.localizedDescription)"
        }
    }

    func draw() {
        guard let audio else {
            background(18)
            noStroke()
            fill(240)
            textSize(16)
            textAlign(.left, .top)
            text(message, 24, 24)
            return
        }

        audio.update()

        // isBeat は update() のたびに立て直される。見えるように残光へ変換する
        if audio.isBeat { flash = 1 }
        flash = max(0, flash - 0.08)
        background(Color(gray: 0.07 + flash * 0.25))

        drawSpectrum(audio.spectrum)
        drawBands(audio)
    }

    /// スペクトルを縦棒で描く
    private func drawSpectrum(_ spectrum: [Float]) {
        guard !spectrum.isEmpty else { return }

        // spectrum は 0Hz から順に並ぶ。上のほうの帯域はふだんの音ではほとんど
        // 動かないので、下 1/4 だけを画面いっぱいに引き伸ばす
        let usable = max(bars, spectrum.count / 4)
        let barWidth = width / Float(bars)

        noStroke()
        for i in 0..<bars {
            let from = i * usable / bars
            let to = max(from + 1, (i + 1) * usable / bars)
            // 1 本のバーが受け持つビンの最大値。平均だと山が埋もれる
            var peak: Float = 0
            for j in from..<min(to, spectrum.count) {
                peak = max(peak, spectrum[j])
            }

            let barHeight = constrain(peak, 0, 1) * (height - 80)
            let hue = map(Float(i), 0, Float(bars), 0.55, 0.95)
            fill(Color(hue: hue, saturation: 0.7, brightness: 0.95))
            rect(Float(i) * barWidth + 1, height - 40 - barHeight, barWidth - 2, barHeight)
        }
    }

    /// 低音・中音・高音のエネルギーを数値で出す
    private func drawBands(_ audio: AudioAnalyzer) {
        // bandEnergy は周波数で指定できる。バーの本数と違い、音楽的な帯域で切れる
        let low = audio.bandEnergy(lowFreq: 20, highFreq: 250)
        let mid = audio.bandEnergy(lowFreq: 250, highFreq: 2000)
        let high = audio.bandEnergy(lowFreq: 2000, highFreq: 8000)

        noStroke()
        fill(Color(gray: 0.9))
        textSize(13)
        textAlign(.left, .top)
        text(String(format: "low %.3f   mid %.3f   high %.3f", low, mid, high), 16, height - 28)
        textAlign(.right, .top)
        text(audio.isBeat ? "BEAT" : " ", width - 16, height - 28)
    }
}
