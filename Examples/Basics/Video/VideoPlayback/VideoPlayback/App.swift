import metaphor

/// ウィンドウにビデオファイルをドラッグ & ドロップして再生するサンプル。
///
/// 操作方法:
/// - ドラッグ & ドロップ: ビデオファイルを読み込み
/// - クリック: 再生 / 一時停止
/// - R キー: 先頭に巻き戻し
/// - L キー: ループ切り替え
/// - +/- キー: 再生速度変更
@main
final class VideoPlayback: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720, title: "Video Playback - Drop a video file here")
    }

    var video: VideoPlayer?
    var message = "Drop a video file here"

    func setup() {
        textAlign(.center, .center)
        textSize(24)

        input.onFileDrop = { [weak self] paths in
            guard let self, let path = paths.first else { return }
            self.loadVideoFile(path)
        }
    }

    func draw() {
        background(0)

        if let video {
            video.update()
            if video.isAvailable {
                // アスペクト比を維持してフィット
                let scale = min(width / video.width, height / video.height)
                let w = video.width * scale
                let h = video.height * scale
                let x = (width - w) / 2
                let y = (height - h) / 2
                image(video, x, y, w, h)

                // 再生情報をオーバーレイ
                fill(Color(gray: 1, alpha: 0.7))
                textAlign(.left, .bottom)
                textSize(14)
                let status = video.isPlaying ? "Playing" : "Paused"
                let loopStatus = video.isLooping ? " [Loop]" : ""
                let info = "\(status)\(loopStatus)  \(formatTime(video.position)) / \(formatTime(video.duration))  x\(String(format: "%.2f", video.rate))"
                text(info, 10, height - 10)
                textAlign(.center, .center)
                textSize(24)
            }
        } else {
            fill(Color(gray: 0.5))
            text(message, width / 2, height / 2)
        }
    }

    func mousePressed() {
        guard let video else { return }
        if video.isPlaying {
            video.pause()
        } else {
            video.play()
        }
    }

    func keyPressed() {
        guard let video else { return }
        switch key {
        case "r":
            video.position = 0
        case "l":
            video.isLooping.toggle()
        case "+", "=":
            video.rate = min(4.0, video.rate + 0.25)
        case "-":
            video.rate = max(0.25, video.rate - 0.25)
        default:
            break
        }
    }

    private func loadVideoFile(_ path: String) {
        do {
            let v = try loadVideo(path)
            v.loop()
            video = v
            message = ""
        } catch {
            message = "Failed to load: \(path)"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
