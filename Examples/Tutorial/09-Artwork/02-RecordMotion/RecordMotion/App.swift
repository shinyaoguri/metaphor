import metaphor

@main
final class RecordMotionSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "RecordMotion", fps: 60)
    }

    let videoPath = "output/motion.mp4"
    let gifPath = "output/motion.gif"
    // GIF を録るあいだだけ落とすフレームレート。GIF 側の fps と必ず揃える
    let gifFrameRate = 15

    var isRecordingVideo = false
    var isRecordingGIF = false
    var recordedFrames = 0
    var status = "V: 動画    G: GIF"

    func draw() {
        background(12)
        drawRing()

        if isRecordingVideo || isRecordingGIF {
            recordedFrames += 1
            let kind = isRecordingVideo ? "動画" : "GIF"
            status = "\(kind)を録画中 \(recordedFrames) フレーム"
        }

        drawStatusBar()
    }

    func keyPressed() {
        if key == "v" || key == "V" {
            toggleVideo()
        } else if key == "g" || key == "G" {
            toggleGIF()
        }
    }

    private func toggleVideo() {
        if isRecordingVideo {
            isRecordingVideo = false
            // 完了は待たずに返る。ファイルが再生できるようになるのはコールバックのあと
            let path = videoPath
            endVideoRecord {
                print("動画を書き出しました: \(path)")
            }
            status = "\(videoPath) を書き出し中…"
        } else if isRecordingGIF {
            status = "GIF の録画中は動画を録れません（G で止めてから）"
        } else {
            recordedFrames = 0
            beginVideoRecord(
                videoPath,
                config: VideoExportConfig(codec: .h264, format: .mp4, fps: 60, bitrate: 20_000_000)
            )
            isRecordingVideo = true
        }
    }

    private func toggleGIF() {
        if isRecordingGIF {
            isRecordingGIF = false
            frameRate(config.fps)
            do {
                // 書き出しに失敗しうる（1 枚も録れていない・書き込めない）ので throws
                try endGIFRecord(gifPath)
                status = "\(gifPath) に \(recordedFrames) フレーム 書き出しました"
            } catch {
                status = "GIF を書き出せませんでした: \(error.localizedDescription)"
            }
        } else if isRecordingVideo {
            status = "動画の録画中は GIF を録れません（V で止めてから）"
        } else {
            recordedFrames = 0
            // GIF は描いたフレームをすべて 1 コマにする。60fps のまま録ると
            // 1 秒の動きが 4 秒の GIF になるので、録るあいだだけ足並みを揃える
            frameRate(gifFrameRate)
            beginGIFRecord(fps: gifFrameRate)
            isRecordingGIF = true
        }
    }

    /// 録画の題材。フレーム番号で動かすので、何回録っても同じ動きになる
    private func drawRing() {
        noStroke()
        let count = 64
        let phase = Float(frameCount) * 0.012

        for index in 0..<count {
            let k = Float(index) / Float(count)
            let angle = k * TWO_PI + phase
            let radius = 95 + sin(k * TWO_PI * 3 + phase * 4) * 42
            let x = width / 2 + cos(angle) * radius
            let y = height / 2 + sin(angle) * radius
            fill(130 + k * 110, 205 - k * 90, 255, 225)
            circle(x, y, 7 + sin(k * TWO_PI * 2 + phase * 3) * 4)
        }
    }

    private func drawStatusBar() {
        noStroke()
        fill(0, 0, 0, 170)
        rect(0, height - 36, width, 36)

        if isRecordingVideo || isRecordingGIF {
            fill(230, 70, 70)
        } else {
            fill(70)
        }
        circle(24, height - 18, 12)

        fill(235)
        textSize(13)
        textAlign(.left, .center)
        text(status, 42, height - 18)
    }
}
