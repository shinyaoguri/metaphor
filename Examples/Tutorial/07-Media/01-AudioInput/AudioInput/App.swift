import metaphor

@main
final class AudioInput: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Audio Input")
    }

    // マイクを開けたときだけ入る。開けなかった理由は message に残す
    var audio: AudioAnalyzer?
    var message = ""

    // 生の volume は 1 フレームごとに跳ねるので、表示用に追従させた値を別に持つ
    var level: Float = 0

    func setup() {
        let input = createAudioInput()
        do {
            // start() を呼ぶまで解析は始まらない。初回はここで権限ダイアログが出る
            try input.start()
            audio = input
        } catch {
            message = "マイクを開けませんでした: \(error.localizedDescription)"
        }
    }

    func draw() {
        background(18)

        guard let audio else {
            noStroke()
            fill(240)
            textSize(16)
            textAlign(.left, .top)
            text(message, 24, 24)
            text("docs/permissions.md に復旧の手順があります", 24, 52)
            return
        }

        // draw() の先頭で 1 回呼ぶ。これで volume / spectrum / isBeat が更新される
        audio.update()

        // volume は RMS を 4 倍した値だが、それでもふつうに話して 0.1 前後にしかならない。
        // さらに 6 倍してから 0...1 に収め、絵に使える範囲へ広げる
        let loudness = constrain(audio.volume * 6, 0, 1)
        // 第 3 部 3.3 のイージング。跳ねる値をそのまま見せると絵が落ち着かない
        level = lerp(level, loudness, 0.25)

        noStroke()
        fill(Color(r: 0.25, g: 0.8, b: 1, alpha: 0.9))
        circle(width / 2, height / 2 - 20, map(level, 0, 1, 40, 280))

        // 追従前の生の値も細い線で重ねる。イージングが何をしているかが見える
        stroke(Color(gray: 1, alpha: 0.5))
        strokeWeight(2)
        noFill()
        circle(width / 2, height / 2 - 20, map(loudness, 0, 1, 40, 280))

        drawMeter(loudness)
    }

    /// 画面下のレベルメーター。数値でも見えるようにしておく
    private func drawMeter(_ loudness: Float) {
        noStroke()
        fill(Color(gray: 1, alpha: 0.15))
        rect(24, height - 48, width - 48, 12)

        fill(Color(r: 0.25, g: 0.8, b: 1))
        rect(24, height - 48, (width - 48) * level, 12)

        fill(Color(gray: 0.85))
        textSize(13)
        textAlign(.left, .top)
        text("volume \(String(format: "%.3f", audio?.volume ?? 0))", 24, height - 28)
    }
}
