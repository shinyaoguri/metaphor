import Foundation
import metaphor

@main
final class VideoPlayback: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Video Playback")
    }

    // 読み込んだ動画は保持しておく。draw() のたびに読み直さない
    var video: VideoPlayer?
    var message = ""

    func setup() {
        // 動画はパッケージのリソースとして同梱している（作り方は README.md）
        guard
            let path = Bundle.module.path(forResource: "loop", ofType: "mp4", inDirectory: "Resources")
        else {
            message = "動画が見つかりませんでした"
            return
        }
        do {
            let player = try loadVideo(path)
            // loop() は「繰り返しを有効にして再生を始める」。play() だと 1 回で止まる
            player.loop()
            video = player
        } catch {
            message = "動画を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func draw() {
        background(12)

        guard let video else {
            noStroke()
            fill(240)
            textSize(16)
            textAlign(.left, .top)
            text(message, 24, 24)
            return
        }

        // draw() の先頭で 1 回呼ぶ。これで texture が現在位置のフレームになる
        video.update()

        // 最初のフレームがデコードされるまでは false。ここを見ずに描くと一瞬黒くなる
        guard video.isAvailable else {
            noStroke()
            fill(Color(gray: 0.6))
            textSize(16)
            textAlign(.center, .center)
            text("読み込み中", width / 2, height / 2)
            return
        }

        // 画像と同じ image()。VideoPlayer をそのまま渡せる。
        // 下 70 ピクセルは再生位置の帯に空けておき、残りへ歪めずに収める
        let stage = height - 70
        let scale = min(width / video.width, stage / video.height)
        let w = video.width * scale
        let h = video.height * scale
        image(video, (width - w) / 2, (stage - h) / 2, w, h)

        drawProgress(video)
    }

    func mousePressed() {
        guard let video else { return }
        // isPlaying は再生中かどうか。押すたびに止める / 続ける
        if video.isPlaying {
            video.pause()
        } else {
            video.play()
        }
    }

    func keyPressed() {
        guard let video, let key else { return }
        switch key {
        case " ":
            // position は秒。代入するとその位置へ飛ぶ（フレーム単位で正確）
            video.position = 0
        case "]":
            // rate は 0.25〜4.0。範囲外は自分で丸める
            video.rate = min(4, video.rate + 0.25)
        case "[":
            video.rate = max(0.25, video.rate - 0.25)
        default:
            break
        }
    }

    /// 再生位置のバーと状態を重ねる
    private func drawProgress(_ video: VideoPlayer) {
        let progress = video.duration > 0 ? Float(video.position / video.duration) : 0

        noStroke()
        fill(Color(gray: 1, alpha: 0.2))
        rect(24, height - 30, width - 48, 6)
        fill(Color(r: 0.4, g: 0.9, b: 1))
        rect(24, height - 30, (width - 48) * progress, 6)

        fill(Color(gray: 0.9))
        textSize(13)
        textAlign(.left, .top)
        let state = video.isPlaying ? "再生中" : "停止中"
        text(
            String(format: "%@  %.1f / %.1f 秒  x%.2f", state, video.position, video.duration, video.rate),
            24, height - 56
        )
        textAlign(.right, .top)
        text("クリック: 再生 / 一時停止   スペース: 先頭へ   [ ]: 速度", width - 24, height - 56)
    }
}
