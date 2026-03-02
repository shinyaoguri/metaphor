import metaphor

/// Feature 2: オーディオリアクティブ
///
/// マイク入力から FFT スペクトラムを取得し、
/// ビート検出で円がパルスするビジュアルを生成する。
/// ※ マイクアクセス許可が必要
@main
final class AudioReactiveExample: Sketch {
    var audio: AudioAnalyzer!
    var beatScale: Float = 1.0

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Audio Reactive")
    }

    func setup() {
        audio = createAudioInput(fftSize: 512)
        do {
            try audio.start()
        } catch {
            print("Audio start failed: \(error)")
            print("マイクへのアクセスを許可してください")
        }
    }

    func draw() {
        audio.update()
        background(Color(gray: 0.02))

        let cx = width / 2
        let cy = height / 2

        // ビートでスケール変化
        if audio.isBeat {
            beatScale = 1.8
        }
        beatScale += (1.0 - beatScale) * deltaTime * 8.0

        // --- 中央の脈動する円 ---
        noStroke()
        let bassEnergy = audio.band(0)
        let circleSize = 100 + bassEnergy * 300 * beatScale
        let hue = (time * 0.05).truncatingRemainder(dividingBy: 1.0)

        for i in stride(from: 5, to: 0, by: -1) {
            let s = circleSize * (1.0 + Float(i) * 0.15)
            let alpha = 0.15 - Float(i) * 0.025
            fill(Color(hue: hue, saturation: 0.7, brightness: 1.0, alpha: alpha))
            circle(cx, cy, s)
        }
        fill(Color(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.9))
        circle(cx, cy, circleSize)

        // --- スペクトラムバー ---
        let spectrum = audio.spectrum
        let barCount = min(spectrum.count, 128)
        let barWidth = width / Float(barCount)

        for i in 0..<barCount {
            let energy = spectrum[i]
            let barHeight = energy * height * 0.4
            let barHue = Float(i) / Float(barCount)

            fill(Color(hue: barHue, saturation: 0.9, brightness: 0.8, alpha: 0.7))
            rect(Float(i) * barWidth, height - barHeight, barWidth - 1, barHeight)
        }

        // --- 波形表示 ---
        let waveform = audio.waveform
        if !waveform.isEmpty {
            stroke(Color(r: 1, g: 1, b: 1, a: 0.3))
            strokeWeight(1.5)
            noFill()
            beginShape(.polygon)
            for i in 0..<waveform.count {
                let x = Float(i) / Float(waveform.count) * width
                let y = cy + waveform[i] * 200
                vertex(x, y)
            }
            endShape()
        }

        // --- 情報表示 ---
        noStroke()
        fill(.white)
        textSize(14)
        textAlign(.left, .top)
        text("Volume: \(String(format: "%.2f", audio.volume))", 20, 20)
        text("Bass: \(String(format: "%.2f", audio.band(0)))", 20, 40)
        text("Mid:  \(String(format: "%.2f", audio.band(1)))", 20, 60)
        text("High: \(String(format: "%.2f", audio.band(2)))", 20, 80)
        if audio.isBeat {
            fill(.red)
            text("BEAT!", 20, 100)
        }
    }
}
